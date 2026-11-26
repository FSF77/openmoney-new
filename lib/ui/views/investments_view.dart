import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
import '../../services/investment_engine.dart';
import '../../services/pdf_report_generator.dart';
import '../../store/money_store.dart';
import '../modals/investment_modals.dart';
import '../theme/liquid_glass.dart';
import '../widgets/csv_export.dart';

class InvestmentsView extends StatefulWidget {
  final MoneyStore store;
  const InvestmentsView({super.key, required this.store});

  @override
  State<InvestmentsView> createState() => _InvestmentsViewState();
}

class _InvestmentsViewState extends State<InvestmentsView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  InvestAssetClass? _classFilter;
  String? _accountFilter;
  String _search = '';
  bool _hideZeroPositions = true;
  bool _showInactive = false;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshQuotes() async {
    setState(() => _refreshing = true);
    try {
      final manualCount = widget.store.db.investAssets
          .where((a) => a.manualPrice && a.assetClass.isVariableIncome)
          .length;
      final count = await widget.store.refreshInvestmentQuotes();
      if (mounted) {
        final manualNote =
            manualCount > 0 ? ' ($manualCount em modo Manual)' : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              count > 0
                  ? '✓ $count cotação(ões) e indicadores atualizados.$manualNote'
                  : 'Indicadores verificados. Nenhuma cotação automática alterada.$manualNote',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _editPriceInline(AssetPositionSummary pos) async {
    final ctrl = TextEditingController(
      text: formatInputCents(pos.currentUnitPriceCents),
    );
    final result = await showDialog<({int? priceCents, bool setAuto})>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Preço Atualizado · ${pos.asset.displayCode}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Novo Preço Unitário',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          if (pos.asset.manualPrice)
            TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop((priceCents: null, setAuto: true)),
              child: const Text('Voltar p/ Automático'),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final c = parseCents(ctrl.text);
              if (c != null && c >= 0) {
                Navigator.of(ctx).pop((priceCents: c, setAuto: false));
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (result != null) {
      if (result.setAuto) {
        widget.store.addOrUpdateInvestAsset(
          pos.asset.copyWith(manualPrice: false),
        );
        await _refreshQuotes();
      } else if (result.priceCents != null) {
        widget.store.updateAssetManualPrice(
          pos.asset.id,
          result.priceCents!,
          manual: true,
        );
      }
    }
  }

  String _custodyNamesForAsset(InvestAsset asset) {
    if (_accountFilter != null) {
      return widget.store.accById(_accountFilter)?.name ?? '';
    }
    final accIds = <String>{};
    for (final op in widget.store.db.investOps) {
      if (op.assetId == asset.id && op.accountId.isNotEmpty) {
        accIds.add(op.accountId);
      }
    }
    if (accIds.isEmpty && asset.accountId.isNotEmpty) {
      accIds.add(asset.accountId);
    }
    final names = accIds
        .map((id) => widget.store.accById(id)?.name)
        .whereType<String>()
        .where((n) => n.isNotEmpty)
        .toList();
    return names.join(' / ');
  }

  void _exportCsv(PortfolioSummary summary) {
    final rows = <List<String>>[
      [
        'Corretora / Conta',
        'Ativo',
        'Nome',
        'Classe',
        'Subtipo',
        'Moeda',
        'Qtde',
        'Valor Compra (Aplicado)',
        'PM Compra',
        'PM Venda',
        'Preço Atualizado',
        'Valor Atual Bruto',
        'IR Estimado',
        'Valor Atual Líquido',
        'Rentabilidade R\$',
        'Rentabilidade %',
        'Lucro Realizado',
        'Proventos',
        'Yield on Cost %',
        'Retorno Total',
        'Indexador',
        'Vencimento',
        'Fonte Cotação',
        'Atualizado em',
      ],
      ...summary.positions.map((p) => [
            _custodyNamesForAsset(p.asset),
            p.asset.displayCode,
            p.asset.name,
            p.asset.assetClass.label,
            p.asset.subType ?? '',
            p.asset.currency,
            formatInvestQty(p.currentQty, p.asset.assetClass),
            formatInputCents(p.currentCostBasisCents),
            formatInputCents(p.avgBuyPriceCents),
            p.avgSellPriceCents > 0 ? formatInputCents(p.avgSellPriceCents) : '',
            formatInputCents(p.currentUnitPriceCents),
            formatInputCents(p.currentGrossValueCents),
            formatInputCents(p.estimatedTaxCents),
            formatInputCents(p.currentNetValueCents),
            formatInputCents(p.unrealizedPnlCents),
            p.unrealizedPnlPct.toStringAsFixed(2),
            formatInputCents(p.realizedPnlCents),
            formatInputCents(p.totalDividendsCents),
            p.yieldOnCostPct.toStringAsFixed(2),
            formatInputCents(p.totalReturnCents),
            p.asset.indexerSummary,
            p.asset.maturityDate != null ? fmtDate(p.asset.maturityDate!) : '',
            p.asset.priceSource ?? '',
            p.asset.priceUpdatedAt ?? '',
          ]),
    ];
    final csv = rows
        .map((r) => r.map((c) => '"${c.replaceAll('"', '""')}"').join(';'))
        .join('\n');
    exportCsvWithFeedback(
      context,
      csv: csv,
      defaultName: 'posicao_investimentos_${todayISO()}.csv',
      title: 'Exportar Posição de Investimentos (CSV)',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final isMobile = MediaQuery.sizeOf(context).width < 760;
    final baseCur = widget.store.baseCurrency;

    final summary = widget.store.portfolioSummary(accountId: _accountFilter);
    final cashBalance =
        widget.store.investmentCashBalance(accountId: _accountFilter);
    final totalPatrimony = cashBalance + summary.totalMarketValueNetCents;

    final filteredPositions = summary.positions.where((p) {
      if (!_showInactive && p.asset.inactive) return false;
      if (_hideZeroPositions && !p.hasOpenPosition) return false;
      if (_classFilter != null && p.asset.assetClass != _classFilter) {
        return false;
      }
      if (_search.trim().isNotEmpty) {
        final q = _search.trim().toLowerCase();
        if (!p.asset.ticker.toLowerCase().contains(q) &&
            !p.asset.name.toLowerCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    final investAccounts = widget.store.db.accounts
        .where((a) => a.isActive && a.type == 'Investimento')
        .toList();

    return Column(
      children: [
        // Cabeçalho & KPIs
        Padding(
          padding: EdgeInsets.fromLTRB(isMobile ? 12 : 20, 14, isMobile ? 12 : 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.candlestick_chart_rounded,
                          color: colors.income, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        'Carteira de Investimentos',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      FilledButton.icon(
                        onPressed: () => showInvestmentOperationModal(
                            context, widget.store),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Nova Operação'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            showInvestmentAssetModal(context, widget.store),
                        icon: const Icon(Icons.add_box_outlined, size: 16),
                        label: const Text('Novo Ativo'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            showB3ImportModal(context, widget.store),
                        icon: const Icon(Icons.upload_file, size: 16),
                        label: const Text('Importar B3'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _refreshing ? null : _refreshQuotes,
                        icon: _refreshing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh, size: 16),
                        label: const Text('Cotações'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            PdfReportGenerator.exportInvestmentPositionPdf(
                          context,
                          widget.store,
                          summary,
                        ),
                        icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                        label: const Text('PDF'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _exportCsv(summary),
                        icon: const Icon(Icons.table_view_outlined, size: 16),
                        label: const Text('CSV'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _KpiChip(
                    colors: colors,
                    label: 'Patrimônio Total (Caixa + Ativos)',
                    value: formatCurrency(totalPatrimony, baseCur),
                    sub: 'Caixa livre: ${formatCurrency(cashBalance, baseCur)}',
                    accent: colors.accent,
                  ),
                  _KpiChip(
                    colors: colors,
                    label: 'Aplicado (Custo)',
                    value: formatCurrency(summary.totalCostBasisCents, baseCur),
                    sub: 'Atualizado: ${formatCurrency(summary.totalMarketValueNetCents, baseCur)}',
                    accent: colors.textPrimary,
                  ),
                  _KpiChip(
                    colors: colors,
                    label: 'Rentabilidade Aberta',
                    value: formatCurrency(summary.totalUnrealizedPnlCents, baseCur),
                    sub: '${summary.totalUnrealizedPnlPct >= 0 ? "+" : ""}${summary.totalUnrealizedPnlPct.toStringAsFixed(2)}%',
                    accent: summary.totalUnrealizedPnlCents >= 0
                        ? colors.income
                        : colors.expense,
                  ),
                  _KpiChip(
                    colors: colors,
                    label: 'Realizado + Proventos',
                    value: formatCurrency(
                      summary.totalRealizedPnlCents + summary.totalDividendsCents,
                      baseCur,
                    ),
                    sub:
                        'Realizado: ${formatCurrency(summary.totalRealizedPnlCents, baseCur)} · Prov: ${formatCurrency(summary.totalDividendsCents, baseCur)}',
                    accent: colors.income,
                  ),
                ],
              ),
            ],
          ),
        ),

        TabBar(
          controller: _tabCtrl,
          isScrollable: isMobile,
          labelColor: colors.accent,
          unselectedLabelColor: colors.textSecondary,
          indicatorColor: colors.accent,
          tabs: const [
            Tab(text: 'Posição Atual'),
            Tab(text: 'Operações'),
            Tab(text: 'Renda Fixa & Tesouro'),
            Tab(text: 'Análise & Alocação'),
          ],
        ),

        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _buildPositionsTab(
                  colors, isMobile, filteredPositions, investAccounts),
              _buildOperationsTab(colors),
              _buildFixedIncomeTab(colors, summary),
              _buildAnalyticsTab(colors, summary, baseCur),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPositionsTab(
    OpenMoneyColors colors,
    bool isMobile,
    List<AssetPositionSummary> positions,
    List<Account> investAccounts,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: isMobile ? double.infinity : 220,
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Buscar ticker ou nome...',
                    prefixIcon: Icon(Icons.search, size: 18),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              if (investAccounts.length > 1)
                SizedBox(
                  width: isMobile ? double.infinity : 230,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _accountFilter,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Corretora',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          'Todas as corretoras',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ...investAccounts.map((a) => DropdownMenuItem<String?>(
                            value: a.id,
                            child: Text(
                              a.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )),
                    ],
                    onChanged: (v) => setState(() => _accountFilter = v),
                  ),
                ),
              FilterChip(
                label: const Text('Todas'),
                selected: _classFilter == null,
                onSelected: (_) => setState(() => _classFilter = null),
              ),
              ...InvestAssetClass.values.map((c) => FilterChip(
                    label: Text(c.label),
                    selected: _classFilter == c,
                    onSelected: (_) => setState(
                        () => _classFilter = _classFilter == c ? null : c),
                  )),
              FilterChip(
                label: const Text('Ocultar zerados'),
                selected: _hideZeroPositions,
                onSelected: (v) => setState(() => _hideZeroPositions = v),
              ),
              FilterChip(
                label: const Text('Mostrar inativos'),
                selected: _showInactive,
                onSelected: (v) => setState(() => _showInactive = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: positions.isEmpty
              ? Center(
                  child: Text(
                    'Nenhum ativo encontrado. Clique em "+ Novo Ativo" ou "Importar B3".',
                    style: TextStyle(color: colors.textSecondary),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final availW = constraints.maxWidth;
                    if (availW < 960) {
                      final cols = availW >= 620 ? 2 : 1;
                      if (cols == 1) {
                        return ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: positions.length,
                          itemBuilder: (ctx, i) =>
                              _buildMobilePositionCard(colors, positions[i]),
                        );
                      }
                      final cardW = (availW - 36) / 2;
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 0,
                          children: positions
                              .map((p) => SizedBox(
                                    width: cardW,
                                    child: _buildMobilePositionCard(colors, p),
                                  ))
                              .toList(),
                        ),
                      );
                    }

                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: availW - 32),
                          child: DataTable(
                            columnSpacing: 14,
                            horizontalMargin: 12,
                            headingRowHeight: 40,
                            dataRowMinHeight: 46,
                            dataRowMaxHeight: 56,
                            columns: const [
                              DataColumn(label: Text('Ativo')),
                              DataColumn(label: Text('Classe')),
                              DataColumn(label: Text('Qtde'), numeric: true),
                              DataColumn(label: Text('Valor Compra'), numeric: true),
                              DataColumn(label: Text('PM Compra'), numeric: true),
                              DataColumn(label: Text('PM Venda'), numeric: true),
                              DataColumn(label: Text('Preço Atual'), numeric: true),
                              DataColumn(label: Text('Valor Atual'), numeric: true),
                              DataColumn(label: Text('Rentab.'), numeric: true),
                              DataColumn(label: Text('Proventos'), numeric: true),
                              DataColumn(label: Text('Ações')),
                            ],
                            rows: positions.map((p) {
                              final cur = p.asset.currency;
                              final pnlColor = p.unrealizedPnlCents >= 0
                                  ? colors.income
                                  : colors.expense;
                              return DataRow(cells: [
                                DataCell(
                                  onTap: () => showAssetOperationsModal(
                                    context,
                                    widget.store,
                                    p.asset,
                                  ),
                                  Tooltip(
                                    message: 'Ver movimentações de ${p.asset.displayCode}',
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          p.asset.displayCode,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: colors.accent,
                                          ),
                                        ),
                                        Text(
                                          p.asset.name,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: colors.textSecondary,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                DataCell(Text(p.asset.assetClass.shortLabel)),
                                DataCell(Text(formatInvestQty(
                                    p.currentQty, p.asset.assetClass))),
                                DataCell(Text(formatCurrency(
                                    p.currentCostBasisCents, cur))),
                                DataCell(Text(
                                    formatCurrency(p.avgBuyPriceCents, cur))),
                                DataCell(Text(p.avgSellPriceCents > 0
                                    ? formatCurrency(p.avgSellPriceCents, cur)
                                    : '—')),
                                DataCell(
                                  InkWell(
                                    onTap: () => _editPriceInline(p),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(formatCurrency(
                                            p.currentUnitPriceCents, cur)),
                                        if (p.asset.manualPrice) ...[
                                          const SizedBox(width: 4),
                                          Tooltip(
                                            message: 'Preço em modo Manual (clique para editar ou voltar ao automático)',
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 4, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: colors.warning.withValues(alpha: 0.18),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                'M',
                                                style: TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: colors.warning,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                        const SizedBox(width: 4),
                                        Icon(Icons.edit_outlined,
                                            size: 13, color: colors.textMuted),
                                      ],
                                    ),
                                  ),
                                ),
                              DataCell(Text(
                                formatCurrency(p.currentNetValueCents, cur),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              )),
                              DataCell(Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    formatCurrency(p.unrealizedPnlCents, cur),
                                    style: TextStyle(
                                        color: pnlColor,
                                        fontWeight: FontWeight.w700),
                                  ),
                                  Text(
                                    '${p.unrealizedPnlPct >= 0 ? "+" : ""}${p.unrealizedPnlPct.toStringAsFixed(2)}%',
                                    style:
                                        TextStyle(fontSize: 11, color: pnlColor),
                                  ),
                                ],
                              )),
                              DataCell(Text(
                                  formatCurrency(p.totalDividendsCents, cur))),
                              DataCell(Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Nova Operação',
                                    icon: const Icon(Icons.add_circle_outline,
                                        size: 18),
                                    onPressed: () =>
                                        showInvestmentOperationModal(
                                      context,
                                      widget.store,
                                      initialAsset: p.asset,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Editar Ativo',
                                    icon: const Icon(Icons.edit_outlined,
                                        size: 18),
                                    onPressed: () => showInvestmentAssetModal(
                                      context,
                                      widget.store,
                                      existing: p.asset,
                                    ),
                                  ),
                                ],
                              )),
                            ]);
                          }).toList(),
                        ),
                      ),
                    ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildMobilePositionCard(
      OpenMoneyColors colors, AssetPositionSummary p) {
    final cur = p.asset.currency;
    final pnlColor =
        p.unrealizedPnlCents >= 0 ? colors.income : colors.expense;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => showAssetOperationsModal(context, widget.store, p.asset),
      child: GlassCard(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${p.asset.displayCode} · ${p.asset.assetClass.shortLabel}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                    Text(p.asset.name,
                        style: TextStyle(
                            fontSize: 12, color: colors.textSecondary)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatCurrency(p.currentNetValueCents, cur),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                  Text(
                    '${formatCurrency(p.unrealizedPnlCents, cur)} (${p.unrealizedPnlPct.toStringAsFixed(2)}%)',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: pnlColor),
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 14),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              Text('Qtde: ${formatInvestQty(p.currentQty, p.asset.assetClass)}',
                  style: const TextStyle(fontSize: 12)),
              Text(
                  'Compra: ${formatCurrency(p.currentCostBasisCents, cur)}',
                  style: const TextStyle(fontSize: 12)),
              Text('PM Compra: ${formatCurrency(p.avgBuyPriceCents, cur)}',
                  style: const TextStyle(fontSize: 12)),
              if (p.avgSellPriceCents > 0)
                Text('PM Venda: ${formatCurrency(p.avgSellPriceCents, cur)}',
                    style: const TextStyle(fontSize: 12)),
              InkWell(
                onTap: () => _editPriceInline(p),
                child: Text(
                  'Atual: ${formatCurrency(p.currentUnitPriceCents, cur)} ✎',
                  style: TextStyle(
                      fontSize: 12,
                      color: colors.accent,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildOperationsTab(OpenMoneyColors colors) {
    final ops = List<InvestOperation>.from(widget.store.db.investOps)
      ..sort((a, b) => b.date.compareTo(a.date));
    if (ops.isEmpty) {
      return Center(
        child: Text('Nenhuma operação registrada ainda.',
            style: TextStyle(color: colors.textSecondary)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: ops.length,
      itemBuilder: (ctx, i) {
        final op = ops[i];
        final asset = widget.store.investAssetById(op.assetId);
        final accName = widget.store.accById(op.accountId)?.name ?? '';
        final cur = asset?.currency ?? widget.store.baseCurrency;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(
              '${op.type.label} · ${asset?.displayCode ?? "Ativo"}${accName.isNotEmpty ? " · $accName" : ""}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${fmtDate(op.date)} · Qtde: ${formatInvestQty(op.quantity, asset?.assetClass ?? InvestAssetClass.stock)} · Unit: ${formatCurrency(op.unitPriceCents, cur)}${op.memo.isNotEmpty ? " · ${op.memo}" : ""}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatCurrency(op.totalCents, cur),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: op.type.isCashIn ? colors.income : colors.textPrimary,
                  ),
                ),
                IconButton(
                  tooltip: 'Editar operação',
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () => showInvestmentOperationModal(
                    context,
                    widget.store,
                    existingOp: op,
                  ),
                ),
                IconButton(
                  tooltip: 'Excluir operação',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () =>
                      widget.store.deleteInvestOperation(op.id),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFixedIncomeTab(
      OpenMoneyColors colors, PortfolioSummary summary) {
    final rf = summary.positions
        .where((p) => p.asset.isFixedIncome && p.hasOpenPosition)
        .toList();
    if (rf.isEmpty) {
      return Center(
        child: Text('Nenhum título de Renda Fixa ou Tesouro Direto ativo.',
            style: TextStyle(color: colors.textSecondary)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: rf.length,
      itemBuilder: (ctx, i) {
        final p = rf[i];
        final cur = p.asset.currency;
        return GlassCard(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${p.asset.displayCode} · ${p.asset.subType ?? p.asset.assetClass.label}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${p.asset.indexerSummary}${p.asset.maturityDate != null ? " · Vence ${fmtDate(p.asset.maturityDate!)}" : ""} · ${p.daysHeld} dias (${p.asset.taxExempt ? "Isento IR" : "IR ${p.irRatePct.toStringAsFixed(1)}%"})',
                      style:
                          TextStyle(fontSize: 12, color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Líquido: ${formatCurrency(p.currentNetValueCents, cur)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    'Aplicado: ${formatCurrency(p.currentCostBasisCents, cur)} · IR: ${formatCurrency(p.estimatedTaxCents, cur)}',
                    style:
                        TextStyle(fontSize: 11.5, color: colors.textSecondary),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAnalyticsTab(
      OpenMoneyColors colors, PortfolioSummary summary, String baseCur) {
    if (summary.byClass.isEmpty) {
      return Center(
        child: Text('Adicione ativos para visualizar a alocação.',
            style: TextStyle(color: colors.textSecondary)),
      );
    }
    final palette = [
      colors.accent,
      colors.income,
      colors.warning,
      colors.accentIndigo,
      Colors.teal,
      Colors.deepOrange,
      Colors.pink,
      Colors.blueGrey,
    ];
    final entries = summary.byClass.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = summary.totalMarketValueNetCents;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: 340,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Alocação por Classe',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 200,
                    child: PieChart(
                      PieChartData(
                        centerSpaceRadius: 42,
                        sectionsSpace: 2,
                        sections: [
                          for (int i = 0; i < entries.length; i++)
                            PieChartSectionData(
                              value: entries[i].value.toDouble(),
                              color: palette[i % palette.length],
                              title: total > 0
                                  ? '${((entries[i].value / total) * 100).toStringAsFixed(0)}%'
                                  : '',
                              titleStyle: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (int i = 0; i < entries.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: palette[i % palette.length],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(entries[i].key.label)),
                          Text(formatCurrency(entries[i].value, baseCur),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiChip extends StatelessWidget {
  final OpenMoneyColors colors;
  final String label;
  final String value;
  final String sub;
  final Color accent;

  const _KpiChip({
    required this.colors,
    required this.label,
    required this.value,
    required this.sub,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 195),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceGlass,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.borderGlass),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: colors.textSecondary)),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: accent)),
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(fontSize: 11, color: colors.textMuted)),
        ],
      ),
    );
  }
}

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

  int _sortColumnIndex = 7; // Valor Atual (padrão decrescente)
  bool _sortAscending = false;

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
    final csv =
        '\uFEFF${rows.map((r) => r.map((c) => '"${c.replaceAll('"', '""')}"').join(';')).join('\r\n')}';
    exportCsvWithFeedback(
      context,
      csv: csv,
      defaultName: 'posicao_investimentos_${todayISO()}.csv',
      title: 'Exportar Posição de Investimentos (CSV)',
    );
  }

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
    });
  }

  void _sortPositions(List<AssetPositionSummary> list) {
    list.sort((a, b) {
      int cmp;
      switch (_sortColumnIndex) {
        case 0:
          cmp = a.asset.displayCode
              .toLowerCase()
              .compareTo(b.asset.displayCode.toLowerCase());
          break;
        case 1:
          cmp = a.asset.assetClass.label
              .toLowerCase()
              .compareTo(b.asset.assetClass.label.toLowerCase());
          break;
        case 2:
          cmp = a.currentQty.compareTo(b.currentQty);
          break;
        case 3:
          cmp = a.currentCostBasisCents.compareTo(b.currentCostBasisCents);
          break;
        case 4:
          cmp = a.avgBuyPriceCents.compareTo(b.avgBuyPriceCents);
          break;
        case 5:
          cmp = a.avgSellPriceCents.compareTo(b.avgSellPriceCents);
          break;
        case 6:
          cmp = a.currentUnitPriceCents.compareTo(b.currentUnitPriceCents);
          break;
        case 7:
          cmp = a.currentNetValueCents.compareTo(b.currentNetValueCents);
          break;
        case 8:
          cmp = a.unrealizedPnlCents.compareTo(b.unrealizedPnlCents);
          break;
        case 9:
          cmp = a.totalDividendsCents.compareTo(b.totalDividendsCents);
          break;
        default:
          cmp = a.currentNetValueCents.compareTo(b.currentNetValueCents);
      }
      if (cmp == 0) {
        cmp = a.asset.displayCode
            .toLowerCase()
            .compareTo(b.asset.displayCode.toLowerCase());
      }
      return _sortAscending ? cmp : -cmp;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final isMobile = MediaQuery.sizeOf(context).width < 720;
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
    _sortPositions(filteredPositions);

    final investAccounts = widget.store.db.accounts
        .where((a) => a.isActive && a.type == 'Investimento')
        .toList();

    return Column(
      children: [
        // 1. Cabeçalho Executivo compacto no padrão AllTransactionsView
        Padding(
          padding: EdgeInsets.fromLTRB(
            isMobile ? 10 : 16,
            isMobile ? 8 : 14,
            isMobile ? 10 : 16,
            isMobile ? 4 : 8,
          ),
          child: GlassCard(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 12 : 16,
              vertical: isMobile ? 10 : 12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.candlestick_chart_rounded,
                      size: isMobile ? 24 : 28,
                      color: colors.income,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Investimentos',
                              style: TextStyle(
                                fontSize: isMobile ? 17 : 20,
                                fontWeight: FontWeight.w900,
                                color: colors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colors.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Carteira',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: colors.accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _CompactActionBtn(
                          icon: Icons.add,
                          label: 'Nova Operação',
                          filled: true,
                          colors: colors,
                          onPressed: () => showInvestmentOperationModal(
                              context, widget.store),
                        ),
                        _CompactActionBtn(
                          icon: Icons.add_box_outlined,
                          label: 'Novo Ativo',
                          colors: colors,
                          onPressed: () =>
                              showInvestmentAssetModal(context, widget.store),
                        ),
                        _CompactActionBtn(
                          icon: Icons.upload_file,
                          label: 'Importar B3',
                          colors: colors,
                          onPressed: () =>
                              showB3ImportModal(context, widget.store),
                        ),
                        _CompactActionBtn(
                          icon: Icons.refresh,
                          label: 'Cotações',
                          loading: _refreshing,
                          colors: colors,
                          onPressed: _refreshing ? null : _refreshQuotes,
                        ),
                        _CompactActionBtn(
                          icon: Icons.picture_as_pdf_outlined,
                          label: 'PDF',
                          colors: colors,
                          onPressed: () =>
                              PdfReportGenerator.exportInvestmentPositionPdf(
                            context,
                            widget.store,
                            summary,
                          ),
                        ),
                        _CompactActionBtn(
                          icon: Icons.table_view_outlined,
                          label: 'CSV',
                          colors: colors,
                          onPressed: () => _exportCsv(summary),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Faixa compacta de KPIs
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _KpiChip(
                      colors: colors,
                      label: 'Patrimônio (Caixa + Ativos)',
                      value: formatCurrency(totalPatrimony, baseCur),
                      sub: 'Caixa livre: ${formatCurrency(cashBalance, baseCur)}',
                      accent: colors.accent,
                    ),
                    _KpiChip(
                      colors: colors,
                      label: 'Aplicado (Custo)',
                      value:
                          formatCurrency(summary.totalCostBasisCents, baseCur),
                      sub:
                          'Atual: ${formatCurrency(summary.totalMarketValueNetCents, baseCur)}',
                      accent: colors.textPrimary,
                    ),
                    _KpiChip(
                      colors: colors,
                      label: 'Rentabilidade Aberta',
                      value: formatCurrency(
                          summary.totalUnrealizedPnlCents, baseCur),
                      sub:
                          '${summary.totalUnrealizedPnlPct >= 0 ? "+" : ""}${summary.totalUnrealizedPnlPct.toStringAsFixed(2)}%',
                      accent: summary.totalUnrealizedPnlCents >= 0
                          ? colors.income
                          : colors.expense,
                    ),
                    _KpiChip(
                      colors: colors,
                      label: 'Realizado + Proventos',
                      value: formatCurrency(
                        summary.totalRealizedPnlCents +
                            summary.totalDividendsCents,
                        baseCur,
                      ),
                      sub:
                          'Realiz.: ${formatCurrency(summary.totalRealizedPnlCents, baseCur)} · Prov.: ${formatCurrency(summary.totalDividendsCents, baseCur)}',
                      accent: colors.income,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // 2. Abas compactas
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 16),
          child: TabBar(
            controller: _tabCtrl,
            isScrollable: isMobile,
            tabAlignment: isMobile ? TabAlignment.start : TabAlignment.fill,
            labelColor: colors.accent,
            unselectedLabelColor: colors.textSecondary,
            indicatorColor: colors.accent,
            labelStyle:
                const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            tabs: const [
              Tab(height: 36, text: 'Posição Atual'),
              Tab(height: 36, text: 'Operações'),
              Tab(height: 36, text: 'Renda Fixa & Tesouro'),
              Tab(height: 36, text: 'Análise & Alocação'),
            ],
          ),
        ),

        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _buildPositionsTab(
                  colors, isMobile, filteredPositions, investAccounts),
              _buildOperationsTab(colors, isMobile),
              _buildFixedIncomeTab(colors, summary, isMobile),
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
    const sortOptions = <(int, String)>[
      (0, 'Ativo'),
      (1, 'Classe'),
      (2, 'Qtde'),
      (3, 'Valor Compra'),
      (4, 'PM Compra'),
      (5, 'PM Venda'),
      (6, 'Preço Atual'),
      (7, 'Valor Atual'),
      (8, 'Rentabilidade'),
      (9, 'Proventos'),
    ];

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            isMobile ? 10 : 16,
            8,
            isMobile ? 10 : 16,
            6,
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: isMobile ? double.infinity : 200,
                height: 34,
                child: TextField(
                  style: const TextStyle(fontSize: 12.5),
                  decoration: const InputDecoration(
                    hintText: 'Buscar ticker ou nome...',
                    prefixIcon: Icon(Icons.search, size: 16),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              if (investAccounts.length > 1)
                SizedBox(
                  width: isMobile ? double.infinity : 200,
                  height: 34,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _accountFilter,
                    isExpanded: true,
                    style: TextStyle(fontSize: 12, color: colors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Corretora',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
              SizedBox(
                width: 175,
                height: 34,
                child: DropdownButtonFormField<int>(
                  initialValue: _sortColumnIndex,
                  isExpanded: true,
                  style: TextStyle(fontSize: 12, color: colors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Ordenar por',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    border: OutlineInputBorder(),
                  ),
                  items: sortOptions
                      .map((opt) => DropdownMenuItem<int>(
                            value: opt.$1,
                            child: Text(
                              opt.$2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) _onSort(v, _sortAscending);
                  },
                ),
              ),
              Tooltip(
                message: _sortAscending ? 'Ordem crescente' : 'Ordem decrescente',
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => _onSort(_sortColumnIndex, !_sortAscending),
                  child: Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: colors.surfaceCard,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: colors.borderGlass),
                    ),
                    child: Icon(
                      _sortAscending
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 16,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ),
              _CompactFilterChip(
                label: 'Todas',
                selected: _classFilter == null,
                colors: colors,
                onSelected: (_) => setState(() => _classFilter = null),
              ),
              ...InvestAssetClass.values.map((c) => _CompactFilterChip(
                    label: c.label,
                    selected: _classFilter == c,
                    colors: colors,
                    onSelected: (_) => setState(
                        () => _classFilter = _classFilter == c ? null : c),
                  )),
              _CompactFilterChip(
                label: 'Ocultar zerados',
                selected: _hideZeroPositions,
                colors: colors,
                onSelected: (v) => setState(() => _hideZeroPositions = v),
              ),
              _CompactFilterChip(
                label: 'Mostrar inativos',
                selected: _showInactive,
                colors: colors,
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
                    style:
                        TextStyle(fontSize: 13, color: colors.textSecondary),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final availW = constraints.maxWidth;
                    if (availW < 960) {
                      final cols = availW >= 620 ? 2 : 1;
                      if (cols == 1) {
                        return ListView.builder(
                          padding: const EdgeInsets.fromLTRB(10, 4, 10, 14),
                          itemCount: positions.length,
                          itemBuilder: (ctx, i) =>
                              _buildMobilePositionCard(colors, positions[i]),
                        );
                      }
                      final cardW = (availW - 32) / 2;
                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(10, 4, 10, 14),
                        child: Wrap(
                          spacing: 10,
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

                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                      child: GlassCard(
                        padding: EdgeInsets.zero,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints:
                                  BoxConstraints(minWidth: availW - 32),
                              child: DataTable(
                                sortColumnIndex: _sortColumnIndex,
                                sortAscending: _sortAscending,
                                columnSpacing: 14,
                                horizontalMargin: 14,
                                headingRowHeight: 36,
                                dataRowMinHeight: 40,
                                dataRowMaxHeight: 46,
                                headingTextStyle: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: colors.textSecondary,
                                ),
                                dataTextStyle: TextStyle(
                                  fontSize: 12,
                                  color: colors.textPrimary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                                columns: [
                                  DataColumn(
                                    label: const Text('Ativo'),
                                    onSort: _onSort,
                                  ),
                                  DataColumn(
                                    label: const Text('Classe'),
                                    onSort: _onSort,
                                  ),
                                  DataColumn(
                                    label: const Text('Qtde'),
                                    numeric: true,
                                    onSort: _onSort,
                                  ),
                                  DataColumn(
                                    label: const Text('Valor Compra'),
                                    numeric: true,
                                    onSort: _onSort,
                                  ),
                                  DataColumn(
                                    label: const Text('PM Compra'),
                                    numeric: true,
                                    onSort: _onSort,
                                  ),
                                  DataColumn(
                                    label: const Text('PM Venda'),
                                    numeric: true,
                                    onSort: _onSort,
                                  ),
                                  DataColumn(
                                    label: const Text('Preço Atual'),
                                    numeric: true,
                                    onSort: _onSort,
                                  ),
                                  DataColumn(
                                    label: const Text('Valor Atual'),
                                    numeric: true,
                                    onSort: _onSort,
                                  ),
                                  DataColumn(
                                    label: const Text('Rentab.'),
                                    numeric: true,
                                    onSort: _onSort,
                                  ),
                                  DataColumn(
                                    label: const Text('Proventos'),
                                    numeric: true,
                                    onSort: _onSort,
                                  ),
                                  const DataColumn(label: Text('Ações')),
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
                                        message:
                                            'Ver movimentações de ${p.asset.displayCode}',
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              p.asset.displayCode,
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w800,
                                                color: colors.accent,
                                              ),
                                            ),
                                            Text(
                                              p.asset.name,
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                color: colors.textSecondary,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                        Text(p.asset.assetClass.shortLabel)),
                                    DataCell(Text(formatInvestQty(
                                        p.currentQty, p.asset.assetClass))),
                                    DataCell(Text(formatCurrency(
                                        p.currentCostBasisCents, cur))),
                                    DataCell(Text(formatCurrency(
                                        p.avgBuyPriceCents, cur))),
                                    DataCell(Text(p.avgSellPriceCents > 0
                                        ? formatCurrency(
                                            p.avgSellPriceCents, cur)
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
                                                message:
                                                    'Preço em modo Manual (clique para editar ou voltar ao automático)',
                                                child: Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 4,
                                                      vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: colors.warning
                                                        .withValues(alpha: 0.18),
                                                    borderRadius:
                                                        BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    'M',
                                                    style: TextStyle(
                                                      fontSize: 9.5,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: colors.warning,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                            const SizedBox(width: 4),
                                            Icon(Icons.edit_outlined,
                                                size: 12,
                                                color: colors.textMuted),
                                          ],
                                        ),
                                      ),
                                    ),
                                    DataCell(Text(
                                      formatCurrency(
                                          p.currentNetValueCents, cur),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700),
                                    )),
                                    DataCell(Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          formatCurrency(
                                              p.unrealizedPnlCents, cur),
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: pnlColor,
                                              fontWeight: FontWeight.w700),
                                        ),
                                        Text(
                                          '${p.unrealizedPnlPct >= 0 ? "+" : ""}${p.unrealizedPnlPct.toStringAsFixed(2)}%',
                                          style: TextStyle(
                                              fontSize: 10.5, color: pnlColor),
                                        ),
                                      ],
                                    )),
                                    DataCell(Text(formatCurrency(
                                        p.totalDividendsCents, cur))),
                                    DataCell(Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Nova Operação',
                                          visualDensity: VisualDensity.compact,
                                          icon: const Icon(
                                              Icons.add_circle_outline,
                                              size: 16),
                                          onPressed: () =>
                                              showInvestmentOperationModal(
                                            context,
                                            widget.store,
                                            initialAsset: p.asset,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Editar Ativo',
                                          visualDensity: VisualDensity.compact,
                                          icon: const Icon(Icons.edit_outlined,
                                              size: 16),
                                          onPressed: () =>
                                              showInvestmentAssetModal(
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
      borderRadius: BorderRadius.circular(12),
      onTap: () => showAssetOperationsModal(context, widget.store, p.asset),
      child: GlassCard(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${p.asset.displayCode} · ${p.asset.assetClass.shortLabel}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          color: colors.accent,
                        ),
                      ),
                      Text(
                        p.asset.name,
                        style: TextStyle(
                            fontSize: 11, color: colors.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatCurrency(p.currentNetValueCents, cur),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: colors.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      '${formatCurrency(p.unrealizedPnlCents, cur)} (${p.unrealizedPnlPct.toStringAsFixed(2)}%)',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: pnlColor),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                    'Qtde: ${formatInvestQty(p.currentQty, p.asset.assetClass)}',
                    style: const TextStyle(fontSize: 11.5)),
                Text(
                    'Compra: ${formatCurrency(p.currentCostBasisCents, cur)}',
                    style: const TextStyle(fontSize: 11.5)),
                Text('PM Compra: ${formatCurrency(p.avgBuyPriceCents, cur)}',
                    style: const TextStyle(fontSize: 11.5)),
                if (p.avgSellPriceCents > 0)
                  Text('PM Venda: ${formatCurrency(p.avgSellPriceCents, cur)}',
                      style: const TextStyle(fontSize: 11.5)),
                InkWell(
                  onTap: () => _editPriceInline(p),
                  child: Text(
                    'Atual: ${formatCurrency(p.currentUnitPriceCents, cur)} ✎',
                    style: TextStyle(
                        fontSize: 11.5,
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

  Widget _buildOperationsTab(OpenMoneyColors colors, bool isMobile) {
    final ops = List<InvestOperation>.from(widget.store.db.investOps)
      ..sort((a, b) => b.date.compareTo(a.date));
    if (ops.isEmpty) {
      return Center(
        child: Text('Nenhuma operação registrada ainda.',
            style: TextStyle(fontSize: 13, color: colors.textSecondary)),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 10 : 16,
        8,
        isMobile ? 10 : 16,
        14,
      ),
      itemCount: ops.length,
      itemBuilder: (ctx, i) {
        final op = ops[i];
        final asset = widget.store.investAssetById(op.assetId);
        final accName = widget.store.accById(op.accountId)?.name ?? '';
        final cur = asset?.currency ?? widget.store.baseCurrency;
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: colors.surfaceCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.borderGlass),
          ),
          child: ListTile(
            dense: true,
            title: Text(
              '${op.type.label} · ${asset?.displayCode ?? "Ativo"}${accName.isNotEmpty ? " · $accName" : ""}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: colors.textPrimary,
              ),
            ),
            subtitle: Text(
              '${fmtDate(op.date)} · Qtde: ${formatInvestQty(op.quantity, asset?.assetClass ?? InvestAssetClass.stock)} · Unit: ${formatCurrency(op.unitPriceCents, cur)}'
              '${op.taxCents > 0 ? " · IR: ${formatCurrency(op.taxCents, cur)}" : ""}'
              '${op.memo.isNotEmpty ? " · ${op.memo}" : ""}',
              style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatCurrency(op.totalCents, cur),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: op.type.isCashIn ? colors.income : colors.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                IconButton(
                  tooltip: 'Editar operação',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  onPressed: () => showInvestmentOperationModal(
                    context,
                    widget.store,
                    existingOp: op,
                  ),
                ),
                IconButton(
                  tooltip: 'Excluir operação',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.delete_outline,
                      size: 17, color: colors.expense),
                  onPressed: () => confirmDeleteInvestOperation(
                    context,
                    widget.store,
                    op,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFixedIncomeTab(
      OpenMoneyColors colors, PortfolioSummary summary, bool isMobile) {
    final rf = summary.positions
        .where((p) => p.asset.isFixedIncome && p.hasOpenPosition)
        .toList();
    if (rf.isEmpty) {
      return Center(
        child: Text('Nenhum título de Renda Fixa ou Tesouro Direto ativo.',
            style: TextStyle(fontSize: 13, color: colors.textSecondary)),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 10 : 16,
        8,
        isMobile ? 10 : 16,
        14,
      ),
      itemCount: rf.length,
      itemBuilder: (ctx, i) {
        final p = rf[i];
        final cur = p.asset.currency;
        return GlassCard(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${p.asset.displayCode} · ${p.asset.subType ?? p.asset.assetClass.label}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${p.asset.indexerSummary}${p.asset.maturityDate != null ? " · Vence ${fmtDate(p.asset.maturityDate!)}" : ""} · ${p.daysHeld} dias (${p.asset.taxExempt ? "Isento IR" : "IR ${p.irRatePct.toStringAsFixed(1)}%"})',
                      style:
                          TextStyle(fontSize: 11.5, color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Líquido: ${formatCurrency(p.currentNetValueCents, cur)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: colors.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    'Aplicado: ${formatCurrency(p.currentCostBasisCents, cur)} · IR: ${formatCurrency(p.estimatedTaxCents, cur)}',
                    style:
                        TextStyle(fontSize: 11, color: colors.textSecondary),
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
            style: TextStyle(fontSize: 13, color: colors.textSecondary)),
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
                  Text('Alocação por Classe',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: colors.textPrimary,
                      )),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 190,
                    child: PieChart(
                      PieChartData(
                        centerSpaceRadius: 40,
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
                          Expanded(
                              child: Text(entries[i].key.label,
                                  style: const TextStyle(fontSize: 12))),
                          Text(formatCurrency(entries[i].value, baseCur),
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w700)),
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

class _CompactActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final bool loading;
  final OpenMoneyColors colors;
  final VoidCallback? onPressed;

  const _CompactActionBtn({
    required this.icon,
    required this.label,
    this.filled = false,
    this.loading = false,
    required this.colors,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final style = filled
        ? ElevatedButton.styleFrom(
            backgroundColor: colors.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            minimumSize: const Size(0, 32),
            textStyle:
                const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          )
        : OutlinedButton.styleFrom(
            foregroundColor: colors.textPrimary,
            side: BorderSide(color: colors.borderGlass),
            backgroundColor: colors.surfaceCard,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            minimumSize: const Size(0, 32),
            textStyle:
                const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          );

    final iconWidget = loading
        ? const SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icon, size: 15);

    if (filled) {
      return ElevatedButton.icon(
        onPressed: onPressed,
        style: style,
        icon: iconWidget,
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: style,
      icon: iconWidget,
      label: Text(label),
    );
  }
}

class _CompactFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final OpenMoneyColors colors;
  final ValueChanged<bool> onSelected;

  const _CompactFilterChip({
    required this.label,
    required this.selected,
    required this.colors,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? colors.accent : colors.textPrimary,
        ),
      ),
      selected: selected,
      onSelected: onSelected,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      backgroundColor: colors.surfaceCard,
      selectedColor: colors.accent.withValues(alpha: 0.14),
      checkmarkColor: colors.accent,
      side: BorderSide(
        color: selected ? colors.accent : colors.borderGlass,
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
      constraints: const BoxConstraints(minWidth: 175),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.borderGlass),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 10.5, color: colors.textSecondary)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: accent,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 1),
          Text(sub, style: TextStyle(fontSize: 10, color: colors.textMuted)),
        ],
      ),
    );
  }
}

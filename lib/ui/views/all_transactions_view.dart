import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
import '../../services/bank_logo_registry.dart';
import '../../services/importers_exporters.dart';
import '../../services/pdf_report_generator.dart';
import '../../store/money_store.dart';
import '../modals/account_multi_select_filter.dart';
import '../modals/batch_delete_modal.dart';
import '../modals/batch_edit_transactions_modal.dart';
import '../modals/transaction_modal.dart';
import '../theme/liquid_glass.dart';
import '../widgets/csv_export.dart';
import '../widgets/datagrid_transaction_table.dart';

enum ConsolidatedPeriodFilter {
  day,
  month,
  year,
}

class AllTransactionsView extends StatefulWidget {
  final MoneyStore store;

  const AllTransactionsView({super.key, required this.store});

  @override
  State<AllTransactionsView> createState() => _AllTransactionsViewState();
}

class _AllTransactionsViewState extends State<AllTransactionsView> {
  ConsolidatedPeriodFilter _periodFilter = ConsolidatedPeriodFilter.day;
  late String _selectedDayIso;
  late String _selectedMonthYm;
  late int _selectedYear;

  bool _cardByInvoice = false;
  Set<String> _selectedAccountIds = {};
  final TextEditingController _searchCtrl = TextEditingController();

  String _categoryFilter = 'all';
  String _tagFilter = 'all';
  String _typeFilter = 'all';
  String _reconciledFilter = 'all';

  bool _selectionMode = false;
  final Set<String> _selectedTxIds = {};

  @override
  void initState() {
    super.initState();
    final today = todayISO();
    _selectedDayIso = today;
    _selectedMonthYm = today.substring(0, 7);
    _selectedYear = int.tryParse(today.substring(0, 4)) ?? DateTime.now().year;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final curDate = dateFromISO(_selectedDayIso);
    final picked = await showDatePicker(
      context: context,
      initialDate: curDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2099, 12, 31),
    );
    if (picked != null) {
      final iso = isoFromDate(picked);
      setState(() {
        _selectedDayIso = iso;
        _selectedMonthYm = iso.substring(0, 7);
        _selectedYear = picked.year;
      });
    }
  }

  void _stepDay(int deltaDays) {
    final cur = dateFromISO(_selectedDayIso);
    final next = cur.add(Duration(days: deltaDays));
    final iso = isoFromDate(next);
    setState(() {
      _selectedDayIso = iso;
      _selectedMonthYm = iso.substring(0, 7);
      _selectedYear = next.year;
    });
  }

  void _resetToToday() {
    final today = todayISO();
    setState(() {
      _selectedDayIso = today;
      _selectedMonthYm = today.substring(0, 7);
      _selectedYear = int.tryParse(today.substring(0, 4)) ?? DateTime.now().year;
    });
  }

  bool get _hasActiveAdvancedFilters =>
      _categoryFilter != 'all' ||
      _tagFilter != 'all' ||
      _typeFilter != 'all' ||
      _reconciledFilter != 'all';

  void _clearAdvancedFilters() {
    setState(() {
      _categoryFilter = 'all';
      _tagFilter = 'all';
      _typeFilter = 'all';
      _reconciledFilter = 'all';
    });
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) {
        _selectedTxIds.clear();
      }
    });
  }

  void _toggleTxSelection(String txId) {
    setState(() {
      if (_selectedTxIds.contains(txId)) {
        _selectedTxIds.remove(txId);
      } else {
        _selectedTxIds.add(txId);
      }
    });
  }

  void _selectAllVisible(List<Transaction> visibleTxs) {
    setState(() {
      for (final tx in visibleTxs) {
        if (tx.auto == true) continue;
        _selectedTxIds.add(tx.id);
      }
    });
  }

  void _batchQuickReconcile(bool reconciled) {
    if (_selectedTxIds.isEmpty) return;
    final count = widget.store.batchUpdateTransactions(
      ids: _selectedTxIds,
      payload: BatchTransactionEditPayload(
        applyReconciled: true,
        reconciled: reconciled,
      ),
    );
    if (count > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reconciled
                ? '$count lançamento(s) marcado(s) como conciliado(s).'
                : '$count lançamento(s) marcado(s) como pendente(s).',
          ),
        ),
      );
    }
  }

  Future<void> _openBatchEditModal() async {
    if (_selectedTxIds.isEmpty) return;
    final updated = await showDialog<int>(
      context: context,
      builder: (_) => BatchEditTransactionsModal(
        store: widget.store,
        selectedIds: Set<String>.from(_selectedTxIds),
      ),
    );
    if (updated != null && updated > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$updated lançamento(s) atualizado(s) em lote.'),
        ),
      );
    }
  }

  Future<void> _confirmBatchDeleteSelection(OpenMoneyColors colors) async {
    if (_selectedTxIds.isEmpty) return;
    final count = _selectedTxIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surfaceCard,
        title: const Text('Excluir Lançamentos Selecionados?'),
        content: Text(
          'Tem certeza que deseja excluir $count lançamento(s) selecionado(s)? Um backup de segurança será criado automaticamente antes da exclusão.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.expense,
              foregroundColor: Colors.white,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final deleted =
          widget.store.batchDeleteTransactionsByIds(_selectedTxIds);
      if (mounted) {
        setState(() {
          _selectedTxIds.clear();
          _selectionMode = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$deleted lançamento(s) excluído(s).'),
          ),
        );
      }
    }
  }

  String _formatPeriodDescription() {
    switch (_periodFilter) {
      case ConsolidatedPeriodFilter.day:
        return 'Dia ${fmtDate(_selectedDayIso)} (${weekdayShort(_selectedDayIso)})';
      case ConsolidatedPeriodFilter.month:
        return 'Mês de ${fmtMonth(_selectedMonthYm)}';
      case ConsolidatedPeriodFilter.year:
        return 'Ano $_selectedYear';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final isMobile = MediaQuery.sizeOf(context).width < 720;

    final query = _searchCtrl.text;
    final res = widget.store.consolidatedTransactions(
      dayIso: _periodFilter == ConsolidatedPeriodFilter.day ? _selectedDayIso : null,
      monthYM: _periodFilter == ConsolidatedPeriodFilter.month ? _selectedMonthYm : null,
      year: _periodFilter == ConsolidatedPeriodFilter.year ? _selectedYear : null,
      cardByInvoice: _cardByInvoice,
      accountFilterIds: _selectedAccountIds.isEmpty ? null : _selectedAccountIds,
      searchQuery: query,
      categoryFilter: _categoryFilter,
      tagFilter: _tagFilter,
      typeFilter: _typeFilter,
      reconciledFilter: _reconciledFilter,
    );

    final txs = res.transactions;
    final orderedTxs = widget.store.sortAscendingDate ? txs : txs.reversed.toList();
    final accMap = {for (final a in widget.store.db.accounts) a.id: a};

    return Column(
      children: [
        // 1. Cabeçalho Executivo com Filtros e Ações
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
                // Linha Superior: Título + Botão Novo Lançamento
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: isMobile ? 26 : 30,
                      color: colors.accent,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Lançamentos',
                                style: TextStyle(
                                  fontSize: isMobile ? 17 : 20,
                                  fontWeight: FontWeight.w900,
                                  color: colors.textPrimary,
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
                                  'Todas as Contas',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: colors.accent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            _formatPeriodDescription(),
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isMobile)
                      IconButton.filled(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Novo Lançamento',
                        icon: const Icon(Icons.add, size: 20),
                        style: IconButton.styleFrom(
                          backgroundColor: colors.accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9),
                          ),
                        ),
                        onPressed: () {
                          showTransactionCreateModal(
                            context,
                            widget.store,
                            initialDateIso: _periodFilter == ConsolidatedPeriodFilter.day
                                ? _selectedDayIso
                                : null,
                          );
                        },
                      )
                    else
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                        icon: const Icon(Icons.add_circle, size: 16),
                        label: const Text(
                          'Novo Lançamento',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        onPressed: () {
                          showTransactionCreateModal(
                            context,
                            widget.store,
                            initialDateIso: _periodFilter == ConsolidatedPeriodFilter.day
                                ? _selectedDayIso
                                : null,
                          );
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // 2. Cards de Resumo no Cabeçalho (Receitas, Despesas e Resultado)
                Row(
                  children: [
                    Expanded(
                      child: _SummaryKpiPill(
                        label: 'Total Receitas',
                        cents: res.incomeCents,
                        currency: res.currency,
                        color: colors.income,
                        icon: Icons.trending_up,
                        colors: colors,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SummaryKpiPill(
                        label: 'Total Despesas',
                        cents: res.expenseCents,
                        currency: res.currency,
                        color: colors.expense,
                        icon: Icons.trending_down,
                        colors: colors,
                        isNegativeDisplay: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SummaryKpiPill(
                        label: 'Resultado Líquido',
                        cents: res.netCents,
                        currency: res.currency,
                        color: res.netCents >= 0 ? colors.income : colors.expense,
                        icon: Icons.account_balance_wallet_outlined,
                        colors: colors,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: colors.borderGlass),
                const SizedBox(height: 10),

                // 3. Barra de Controles e Filtros
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Seletor de Período: Dia / Mês / Ano
                    SegmentedButton<ConsolidatedPeriodFilter>(
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        textStyle: WidgetStatePropertyAll(
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                      segments: const [
                        ButtonSegment(
                          value: ConsolidatedPeriodFilter.day,
                          label: Text('Dia'),
                        ),
                        ButtonSegment(
                          value: ConsolidatedPeriodFilter.month,
                          label: Text('Mês'),
                        ),
                        ButtonSegment(
                          value: ConsolidatedPeriodFilter.year,
                          label: Text('Ano'),
                        ),
                      ],
                      selected: {_periodFilter},
                      onSelectionChanged: (s) =>
                          setState(() => _periodFilter = s.first),
                    ),

                    // Controles específicos de acordo com o modo
                    if (_periodFilter == ConsolidatedPeriodFilter.day) ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            icon: const Icon(Icons.chevron_left, size: 20),
                            tooltip: 'Dia anterior',
                            onPressed: () => _stepDay(-1),
                          ),
                          InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: _pickDay,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                border: Border.all(color: colors.borderGlass),
                                borderRadius: BorderRadius.circular(8),
                                color: colors.surfaceGlass,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.calendar_today_outlined, size: 15),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${fmtDate(_selectedDayIso)} (${weekdayShort(_selectedDayIso)})',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            icon: const Icon(Icons.chevron_right, size: 20),
                            tooltip: 'Próximo dia',
                            onPressed: () => _stepDay(1),
                          ),
                        ],
                      ),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 32),
                        ),
                        onPressed: _resetToToday,
                        child: const Text('Hoje', style: TextStyle(fontSize: 12)),
                      ),
                    ] else if (_periodFilter == ConsolidatedPeriodFilter.month) ...[
                      MonthYearPickerBar(
                        currentMonthYM: _selectedMonthYm,
                        availableYears: widget.store.allYearsInDatabase(),
                        onMonthChanged: (ym) => setState(() => _selectedMonthYm = ym),
                      ),
                    ] else ...[
                      // Seletor de Ano
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            icon: const Icon(Icons.chevron_left, size: 20),
                            onPressed: () => setState(() => _selectedYear -= 1),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              border: Border.all(color: colors.borderGlass),
                              borderRadius: BorderRadius.circular(8),
                              color: colors.surfaceGlass,
                            ),
                            child: Text(
                              'Ano $_selectedYear',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            icon: const Icon(Icons.chevron_right, size: 20),
                            onPressed: () => setState(() => _selectedYear += 1),
                          ),
                        ],
                      ),
                    ],

                    // Filtro de Cartão: Data do Lançamento vs. Por Fatura
                    FilterChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        _cardByInvoice
                            ? 'Cartão: Fatura (Pagamento)'
                            : 'Cartão: Data do Lançamento',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                      ),
                      selected: _cardByInvoice,
                      onSelected: (v) => setState(() => _cardByInvoice = v),
                    ),

                    // Filtro Multicontas
                    AccountMultiSelectFilter(
                      store: widget.store,
                      selectedAccountIds: _selectedAccountIds,
                      onSelectionChanged: (s) => setState(() => _selectedAccountIds = s),
                    ),

                    // Ferramentas de Previsões
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        minimumSize: const Size(0, 34),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      icon: const Icon(Icons.auto_fix_high, size: 14),
                      label: const Text('Previsões', style: TextStyle(fontSize: 11.5)),
                      onPressed: () {
                        final res = widget.store.adjustPredictions(
                          _periodFilter == ConsolidatedPeriodFilter.month
                              ? _selectedMonthYm
                              : widget.store.month,
                        );
                        showPredictionsAdjustModal(context, res);
                      },
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Modo de abatimento das previsões',
                      icon: const Icon(Icons.tune, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      initialValue: widget.store.db.predMode,
                      onSelected: widget.store.setPredMode,
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'month', child: Text('Por mês')),
                        PopupMenuItem(
                            value: 'invoice', child: Text('Por fatura (cartão)')),
                      ],
                    ),

                    // Exportação CSV
                    Tooltip(
                      message: 'Exportar CSV',
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          minimumSize: const Size(36, 34),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: txs.isEmpty
                            ? null
                            : () {
                                final periodTag = _periodFilter == ConsolidatedPeriodFilter.day
                                    ? _selectedDayIso
                                    : (_periodFilter == ConsolidatedPeriodFilter.month
                                        ? _selectedMonthYm
                                        : '$_selectedYear');
                                final defaultName =
                                    'openmoney-lancamentos-$periodTag.csv';
                                final csvContent = CSVExporter.generateCSV(
                                  transactions: txs,
                                  accounts: widget.store.db.accounts,
                                  baseCurrency: widget.store.baseCurrency,
                                  rates: widget.store.db.rates,
                                  allTransactionsForPairs: widget.store.db.txs,
                                );
                                exportCsvWithFeedback(
                                  context,
                                  csv: csvContent,
                                  defaultName: defaultName,
                                  title: 'Exportar Lançamentos (CSV)',
                                );
                              },
                        child: const Icon(Icons.download, size: 16),
                      ),
                    ),

                    // Exportação PDF
                    Tooltip(
                      message: 'Exportar PDF',
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          minimumSize: const Size(36, 34),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: txs.isEmpty
                            ? null
                            : () {
                                final periodTitle = _formatPeriodDescription();
                                final pdfBytes = PdfReportGenerator
                                    .buildConsolidatedTransactionsPdfBytes(
                                  store: widget.store,
                                  periodTitle: periodTitle,
                                  transactions: txs,
                                  incomeCents: res.incomeCents,
                                  expenseCents: res.expenseCents,
                                  netCents: res.netCents,
                                  summaryCurrency: res.currency,
                                );
                                final periodTag = _periodFilter == ConsolidatedPeriodFilter.day
                                    ? _selectedDayIso
                                    : (_periodFilter == ConsolidatedPeriodFilter.month
                                        ? _selectedMonthYm
                                        : '$_selectedYear');
                                final defaultName =
                                    'lancamentos-$periodTag.pdf';
                                PdfReportGenerator.saveAndOpenPdfBytes(
                                  context,
                                  pdfBytes: pdfBytes,
                                  defaultFileName: defaultName,
                                );
                              },
                        child: const Icon(Icons.picture_as_pdf, size: 16),
                      ),
                    ),

                    // Campo de Busca
                    Container(
                      width: isMobile ? 180 : 210,
                      height: 34,
                      decoration: BoxDecoration(
                        color: colors.surfaceGlass,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colors.borderGlass),
                      ),
                      child: TextField(
                        controller: _searchCtrl,
                        style: const TextStyle(fontSize: 12),
                        textAlignVertical: TextAlignVertical.center,
                        decoration: InputDecoration(
                          hintText: 'Filtrar lançamentos...',
                          hintStyle: TextStyle(
                            fontSize: 12,
                            color: colors.textMuted,
                          ),
                          prefixIcon: Icon(
                            Icons.filter_list,
                            size: 16,
                            color: colors.textSecondary,
                          ),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 14),
                                  splashRadius: 14,
                                  onPressed: () =>
                                      setState(() => _searchCtrl.clear()),
                                )
                              : null,
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),

                    // Alternador Lista Diária vs Datagrid + Ordenação de Data
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          tooltip: widget.store.sortAscendingDate
                              ? 'Ordem de Data: Mais antigos primeiro (Clique para Mais recentes primeiro)'
                              : 'Ordem de Data: Mais recentes primeiro (Clique para Mais antigos primeiro)',
                          icon: Icon(
                            widget.store.sortAscendingDate
                                ? Icons.arrow_upward_rounded
                                : Icons.arrow_downward_rounded,
                            size: 16,
                            color: colors.accent,
                          ),
                          onPressed: widget.store.toggleSortAscendingDate,
                        ),
                        const SizedBox(width: 4),
                        Container(
                          height: 14,
                          width: 1,
                          color: colors.borderGlass,
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          tooltip: 'Visualização em Lista',
                          icon: Icon(
                            Icons.view_agenda_outlined,
                            size: 16,
                            color: widget.store.ledgerViewMode == 'list'
                                ? colors.accent
                                : colors.textMuted,
                          ),
                          onPressed: () =>
                              widget.store.setLedgerViewMode('list'),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          tooltip: 'Visualização em Tabela Datagrid',
                          icon: Icon(
                            Icons.table_chart_outlined,
                            size: 16,
                            color: widget.store.ledgerViewMode == 'table'
                                ? colors.accent
                                : colors.textMuted,
                          ),
                          onPressed: () =>
                              widget.store.setLedgerViewMode('table'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildAdvancedFiltersBar(colors, isMobile),
              ],
            ),
          ),
        ),
        if (_selectionMode)
          _buildSelectionActionBar(
            orderedTxs: orderedTxs,
            currency: res.currency,
            colors: colors,
            isMobile: isMobile,
          ),

        // 2. Listagem Cronológica dos Lançamentos Consolidados
        Expanded(
          child: orderedTxs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        size: 44,
                        color: colors.textMuted,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _searchCtrl.text.isNotEmpty
                            ? 'Nenhum lançamento encontrado para "${_searchCtrl.text.trim()}".'
                            : 'Nenhum lançamento no período selecionado.',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_searchCtrl.text.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          icon: const Icon(Icons.clear, size: 14),
                          label: const Text('Limpar busca'),
                          onPressed: () => setState(() => _searchCtrl.clear()),
                        ),
                      ],
                    ],
                  ),
                )
              : (widget.store.ledgerViewMode == 'table'
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      children: [
                        DatagridTransactionTable(
                          transactions: orderedTxs,
                          store: widget.store,
                          showAccountColumn: true,
                        ),
                      ],
                    )
                  : _buildGroupedTransactionsList(
                      context,
                      txs: orderedTxs,
                      accMap: accMap,
                      summaryCurrency: res.currency,
                      colors: colors,
                      isMobile: isMobile,
                    )),
        ),
      ],
    );
  }

  Widget _buildGroupedTransactionsList(
    BuildContext context, {
    required List<Transaction> txs,
    required Map<String, Account> accMap,
    required String summaryCurrency,
    required OpenMoneyColors colors,
    required bool isMobile,
  }) {
    if (_periodFilter == ConsolidatedPeriodFilter.year) {
      // Visão Anual: Agrupa por Mês e depois por Dia
      final monthGroups = <String, List<Transaction>>{};
      for (final t in txs) {
        final ym = t.date.length >= 7 ? t.date.substring(0, 7) : 'Outros';
        monthGroups.putIfAbsent(ym, () => []).add(t);
      }
      final sortedMonths = monthGroups.keys.toList()..sort();
      final displayMonths = widget.store.sortAscendingDate
          ? sortedMonths
          : sortedMonths.reversed.toList();

      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: displayMonths.length,
        itemBuilder: (context, idx) {
          final ym = displayMonths[idx];
          final monthTxs = monthGroups[ym]!;

          int mInc = 0;
          int mExp = 0;
          for (final t in monthTxs) {
            if (t.xfer == null && t.peer == null && t.auto != true) {
              final conv = widget.store.convertTxToCurrency(t, summaryCurrency);
              if (conv > 0) mInc += conv;
              if (conv < 0) mExp += conv.abs();
            }
          }
          final mNet = mInc - mExp;

          final dayGroups = _buildDayGroups(monthTxs);

          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header do Mês
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: colors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.borderGlass),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        fmtMonth(ym).toUpperCase(),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: colors.accent,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Wrap(
                        spacing: 12,
                        children: [
                          Text(
                            'Rec: +${formatCurrency(mInc, summaryCurrency)}',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: colors.income,
                            ),
                          ),
                          Text(
                            'Desp: -${formatCurrency(mExp, summaryCurrency)}',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: colors.expense,
                            ),
                          ),
                          Text(
                            'Res: ${formatCurrency(mNet, summaryCurrency)}',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: mNet >= 0 ? colors.income : colors.expense,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                ...dayGroups.map(
                  (dg) => _buildDayCard(
                    context,
                    dg: dg,
                    accMap: accMap,
                    summaryCurrency: summaryCurrency,
                    colors: colors,
                    isMobile: isMobile,
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    // Visão Diária ou Mensal: Agrupa por Dia
    final dayGroups = _buildDayGroups(txs);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: dayGroups.length,
      itemBuilder: (context, idx) {
        final dg = dayGroups[idx];
        return _buildDayCard(
          context,
          dg: dg,
          accMap: accMap,
          summaryCurrency: summaryCurrency,
          colors: colors,
          isMobile: isMobile,
        );
      },
    );
  }

  List<_ConsolidatedDayGroup> _buildDayGroups(List<Transaction> txList) {
    final groups = <_ConsolidatedDayGroup>[];
    for (final tx in txList) {
      if (groups.isEmpty || groups.last.date != tx.date) {
        groups.add(_ConsolidatedDayGroup(date: tx.date, items: [tx]));
      } else {
        groups.last.items.add(tx);
      }
    }
    return groups;
  }

  Widget _buildDayCard(
    BuildContext context, {
    required _ConsolidatedDayGroup dg,
    required Map<String, Account> accMap,
    required String summaryCurrency,
    required OpenMoneyColors colors,
    required bool isMobile,
  }) {
    int dayInc = 0;
    int dayExp = 0;
    for (final t in dg.items) {
      if (t.xfer == null && t.peer == null && t.auto != true) {
        final conv = widget.store.convertTxToCurrency(t, summaryCurrency);
        if (conv > 0) dayInc += conv;
        if (conv < 0) dayExp += conv.abs();
      }
    }
    final dayNet = dayInc - dayExp;

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ...dg.items.map((tx) {
            final acc = accMap[tx.acc];
            final isPred = isPredictionPayee(tx.payee);
            return Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: colors.borderGlass.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: ListTile(
                dense: true,
                contentPadding: isMobile
                    ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
                    : null,
                horizontalTitleGap: isMobile ? 6 : null,
                onTap: () {
                  final origTx = widget.store.db.txs
                      .firstWhere((t) => t.id == tx.id, orElse: () => tx);
                  showTransactionEditModal(context, widget.store, origTx);
                },
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_selectionMode)
                      Checkbox(
                        value: tx.auto == true
                            ? false
                            : _selectedTxIds.contains(tx.id),
                        onChanged: tx.auto == true
                            ? null
                            : (_) => _toggleTxSelection(tx.id),
                        activeColor: colors.accent,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    IconButton(
                      visualDensity: isMobile ? VisualDensity.compact : null,
                      padding: isMobile ? const EdgeInsets.all(4) : null,
                      constraints: isMobile ? const BoxConstraints() : null,
                      tooltip: tx.rec
                          ? 'Conciliado (Clique para desmarcar)'
                          : 'Pendente (Clique para conciliar)',
                      icon: Icon(
                        tx.rec ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: tx.rec ? colors.income : colors.textMuted,
                        size: isMobile ? 18 : 20,
                      ),
                      onPressed: () => widget.store.toggleReconciled(tx.id),
                    ),
                    Container(
                      width: isMobile ? 22 : 26,
                      alignment: Alignment.center,
                      child: Text(
                        tx.date.split('-').last,
                        style: TextStyle(
                          fontSize: isMobile ? 11.5 : 12.5,
                          fontWeight: FontWeight.w700,
                          color: colors.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
                title: Row(
                  children: [
                    if (acc != null) ...[
                      AccountLogoWidget(
                        account: acc,
                        size: isMobile ? 16 : 18,
                        cornerRadius: 4,
                      ),
                      const SizedBox(width: 6),
                      Container(
                        constraints: const BoxConstraints(maxWidth: 130),
                        child: Text(
                          acc.name,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: colors.accent,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      flex: 3,
                      child: Text(
                        tx.payee,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: isMobile ? 12.5 : 13.5,
                          color: colors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!isMobile) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text('•',
                            style: TextStyle(
                                fontSize: 12, color: colors.textMuted)),
                      ),
                      Flexible(
                        flex: 4,
                        child: Text(
                          tx.cat.isEmpty ? 'Sem categoria' : tx.cat,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: tx.cat.isEmpty
                                ? colors.textMuted
                                : colors.textSecondary,
                            fontStyle: tx.cat.isEmpty
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isPred) ...[
                        const SizedBox(width: 5),
                        StatusBadge(
                          text: 'PREVISÃO',
                          color: colors.accentCyan,
                          fontSize: 8.5,
                        ),
                      ],
                      if (tx.recId != null) ...[
                        const SizedBox(width: 5),
                        StatusBadge(
                          text: recurrenceFrequencyLabel(tx.recFreq).toUpperCase(),
                          color: colors.accent,
                          icon: Icons.repeat,
                          fontSize: 8.5,
                        ),
                      ],
                      if (tx.auto == true) ...[
                        const SizedBox(width: 5),
                        StatusBadge(
                          text: 'FATURA AUTO',
                          color: colors.warning,
                          fontSize: 8.5,
                        ),
                      ],
                      if (tx.ik != null && tx.ik!.isNotEmpty && tx.auto != true) ...[
                        const SizedBox(width: 5),
                        StatusBadge(
                          text: 'FATURA ${formatInvoiceKeyForDisplay(tx.ik!)}',
                          color: colors.accentIndigo,
                          icon: Icons.receipt_outlined,
                          fontSize: 8.5,
                        ),
                      ],
                      if (tx.tags != null && tx.tags!.isNotEmpty) ...[
                        const SizedBox(width: 5),
                        ..._buildTagChips(tx.tags!, colors),
                      ],
                    ],
                  ],
                ),
                subtitle: isMobile
                    ? Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              tx.cat.isEmpty ? 'Sem categoria' : tx.cat,
                              style: TextStyle(
                                fontSize: 11,
                                color: tx.cat.isEmpty
                                    ? colors.textMuted
                                    : colors.textSecondary,
                              ),
                            ),
                            if (tx.memo.trim().isNotEmpty)
                              Text('• ${tx.memo.trim()}',
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      color: colors.textSecondary)),
                            if (isPred)
                              StatusBadge(
                                text: 'PREVISÃO',
                                color: colors.accentCyan,
                                fontSize: 8.5,
                              ),
                            if (tx.auto == true)
                              StatusBadge(
                                text: 'FATURA AUTO',
                                color: colors.warning,
                                fontSize: 8.5,
                              ),
                            if (tx.ik != null &&
                                tx.ik!.isNotEmpty &&
                                tx.auto != true)
                              StatusBadge(
                                text: 'FAT. ${formatInvoiceKeyForDisplay(tx.ik!)}',
                                color: colors.accentIndigo,
                                fontSize: 8.5,
                              ),
                            if (tx.tags != null && tx.tags!.isNotEmpty)
                              ..._buildTagChips(tx.tags!, colors),
                          ],
                        ),
                      )
                    : (tx.memo.trim().isNotEmpty
                        ? Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              tx.memo.trim(),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: colors.textSecondary,
                              ),
                            ),
                          )
                        : null),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      formatCurrency(
                          tx.amt, acc?.effectiveCurrency ?? widget.store.baseCurrency),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: isMobile ? 12.5 : 13.5,
                        color: tx.amt >= 0 ? colors.income : colors.expense,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    SizedBox(width: isMobile ? 2 : 4),
                    if (tx.auto != true) ...[
                      IconButton(
                        visualDensity: isMobile ? VisualDensity.compact : null,
                        padding: isMobile ? const EdgeInsets.all(3) : null,
                        constraints: isMobile ? const BoxConstraints() : null,
                        tooltip: 'Copiar Lançamento',
                        icon: Icon(
                          Icons.copy_rounded,
                          size: isMobile ? 15 : 16,
                          color: colors.textMuted,
                        ),
                        onPressed: () {
                          final origTx = widget.store.db.txs
                              .firstWhere((t) => t.id == tx.id, orElse: () => tx);
                          showTransactionCopyModal(
                            context,
                            widget.store,
                            origTx,
                          );
                        },
                      ),
                      if (!isMobile) const SizedBox(width: 2),
                    ],
                    IconButton(
                      visualDensity: isMobile ? VisualDensity.compact : null,
                      padding: isMobile ? const EdgeInsets.all(3) : null,
                      constraints: isMobile ? const BoxConstraints() : null,
                      tooltip: 'Excluir Lançamento',
                      icon: Icon(
                        Icons.delete_outline,
                        size: isMobile ? 16 : 17,
                        color: colors.textMuted,
                      ),
                      onPressed: tx.auto == true
                          ? null
                          : () => showDeleteTransactionDialog(
                                context,
                                widget.store,
                                tx,
                              ),
                    ),
                  ],
                ),
              ),
            );
          }),
          // Rodapé do Dia
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: colors.bgPrimary.withValues(alpha: 0.35),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              border: Border(
                top: BorderSide(color: colors.borderGlass),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${fmtDate(dg.date)} · ${weekdayShort(dg.date).toUpperCase()}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: colors.accent,
                  ),
                ),
                Wrap(
                  spacing: 12,
                  children: [
                    Text(
                      'Receitas: +${formatCurrency(dayInc, summaryCurrency)}',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: colors.income,
                      ),
                    ),
                    Text(
                      'Despesas: -${formatCurrency(dayExp, summaryCurrency)}',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: colors.expense,
                      ),
                    ),
                    Text(
                      'Resultado: ${formatCurrency(dayNet, summaryCurrency)}',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: dayNet >= 0 ? colors.income : colors.expense,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTagChips(List<String> tags, OpenMoneyColors colors) {
    return tags.map((tag) {
      return Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
        decoration: BoxDecoration(
          color: colors.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.accent.withValues(alpha: 0.3)),
        ),
        child: Text(
          '#$tag',
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
            color: colors.accent,
          ),
        ),
      );
    }).toList();
  }

  Widget _buildAdvancedFiltersBar(OpenMoneyColors colors, bool isMobile) {
    final categories = widget.store.allCatNames();
    final tags = widget.store.allTags;

    Widget buildDropdown<T>({
      required String label,
      required T value,
      required List<DropdownMenuItem<T>> items,
      required ValueChanged<T?> onChanged,
      double width = 155,
    }) {
      return SizedBox(
        width: isMobile ? null : width,
        child: DropdownButtonFormField<T>(
          initialValue: value,
          isExpanded: true,
          isDense: true,
          dropdownColor: colors.surfaceCard,
          style: TextStyle(fontSize: 12, color: colors.textPrimary),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: TextStyle(fontSize: 11, color: colors.textMuted),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.borderGlass),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.borderGlass),
            ),
          ),
          items: items,
          onChanged: onChanged,
        ),
      );
    }

    final catValue = (_categoryFilter == 'all' ||
            _categoryFilter == '__uncategorized__' ||
            categories.contains(_categoryFilter))
        ? _categoryFilter
        : 'all';
    final tagValue = (_tagFilter == 'all' ||
            _tagFilter == '__untagged__' ||
            tags.any((t) => t.toLowerCase() == _tagFilter.toLowerCase()))
        ? _tagFilter
        : 'all';

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        buildDropdown<String>(
          label: 'Categoria',
          value: catValue,
          width: 175,
          items: [
            const DropdownMenuItem(value: 'all', child: Text('Todas')),
            const DropdownMenuItem(
              value: '__uncategorized__',
              child: Text('Sem categoria'),
            ),
            ...categories.map(
              (c) => DropdownMenuItem(
                value: c,
                child: Text(
                  c.replaceAll(':', ' › '),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _categoryFilter = v);
          },
        ),
        buildDropdown<String>(
          label: 'Tag',
          value: tagValue,
          width: 145,
          items: [
            const DropdownMenuItem(value: 'all', child: Text('Todas')),
            const DropdownMenuItem(value: '__untagged__', child: Text('Sem tag')),
            ...tags.map(
              (t) => DropdownMenuItem(
                value: t,
                child: Text('#$t', overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _tagFilter = v);
          },
        ),
        buildDropdown<String>(
          label: 'Tipo',
          value: _typeFilter,
          width: 130,
          items: const [
            DropdownMenuItem(value: 'all', child: Text('Todos')),
            DropdownMenuItem(value: 'expense', child: Text('Despesas')),
            DropdownMenuItem(value: 'income', child: Text('Receitas')),
            DropdownMenuItem(value: 'transfer', child: Text('Transferências')),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _typeFilter = v);
          },
        ),
        buildDropdown<String>(
          label: 'Conciliação',
          value: _reconciledFilter,
          width: 130,
          items: const [
            DropdownMenuItem(value: 'all', child: Text('Todos')),
            DropdownMenuItem(value: 'reconciled', child: Text('Conciliados')),
            DropdownMenuItem(value: 'pending', child: Text('Pendentes')),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _reconciledFilter = v);
          },
        ),
        if (_hasActiveAdvancedFilters)
          TextButton.icon(
            onPressed: _clearAdvancedFilters,
            icon: const Icon(Icons.filter_alt_off, size: 15),
            label: const Text('Limpar filtros', style: TextStyle(fontSize: 12)),
          ),
        OutlinedButton.icon(
          onPressed: _toggleSelectionMode,
          icon: Icon(
            _selectionMode ? Icons.check_box : Icons.check_box_outline_blank,
            size: 16,
            color: _selectionMode ? colors.accent : colors.textSecondary,
          ),
          label: Text(
            _selectionMode ? 'Sair da Seleção' : 'Selecionar',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _selectionMode ? colors.accent : colors.textPrimary,
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(
              color: _selectionMode ? colors.accent : colors.borderGlass,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectionActionBar({
    required List<Transaction> orderedTxs,
    required String currency,
    required OpenMoneyColors colors,
    required bool isMobile,
  }) {
    final selectableTxs = orderedTxs.where((t) => t.auto != true).toList();
    int selectedNet = 0;
    for (final tx in selectableTxs) {
      if (_selectedTxIds.contains(tx.id)) {
        selectedNet += widget.store.convertTxToCurrency(tx, currency);
      }
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 10 : 16,
        0,
        isMobile ? 10 : 16,
        6,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colors.accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.accent.withValues(alpha: 0.35)),
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${_selectedTxIds.length} selecionado(s)',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: colors.accent,
              ),
            ),
            if (_selectedTxIds.isNotEmpty)
              Text(
                '(${formatCurrency(selectedNet, currency)})',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selectedNet >= 0 ? colors.income : colors.expense,
                ),
              ),
            TextButton(
              onPressed: selectableTxs.isEmpty
                  ? null
                  : () => _selectAllVisible(selectableTxs),
              child: const Text('Selecionar todos',
                  style: TextStyle(fontSize: 12)),
            ),
            if (_selectedTxIds.isNotEmpty)
              TextButton(
                onPressed: () => setState(() => _selectedTxIds.clear()),
                child: const Text('Limpar', style: TextStyle(fontSize: 12)),
              ),
            ElevatedButton.icon(
              onPressed:
                  _selectedTxIds.isEmpty ? null : _openBatchEditModal,
              icon: const Icon(Icons.edit, size: 15),
              label: const Text('Editar em Lote',
                  style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _selectedTxIds.isEmpty
                  ? null
                  : () => _batchQuickReconcile(true),
              icon: Icon(Icons.check_circle_outline,
                  size: 15, color: colors.income),
              label: const Text('Conciliar', style: TextStyle(fontSize: 12)),
            ),
            OutlinedButton.icon(
              onPressed: _selectedTxIds.isEmpty
                  ? null
                  : () => _batchQuickReconcile(false),
              icon: Icon(Icons.radio_button_unchecked,
                  size: 15, color: colors.textMuted),
              label: const Text('Pendente', style: TextStyle(fontSize: 12)),
            ),
            OutlinedButton.icon(
              onPressed: _selectedTxIds.isEmpty
                  ? null
                  : () => _confirmBatchDeleteSelection(colors),
              icon: Icon(Icons.delete_outline,
                  size: 15, color: colors.expense),
              label: Text(
                'Excluir',
                style: TextStyle(fontSize: 12, color: colors.expense),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsolidatedDayGroup {
  final String date;
  final List<Transaction> items;

  _ConsolidatedDayGroup({required this.date, required this.items});
}

class _SummaryKpiPill extends StatelessWidget {
  final String label;
  final int cents;
  final String currency;
  final Color color;
  final IconData icon;
  final OpenMoneyColors colors;
  final bool isNegativeDisplay;

  const _SummaryKpiPill({
    required this.label,
    required this.cents,
    this.currency = 'BRL',
    required this.color,
    required this.icon,
    required this.colors,
    this.isNegativeDisplay = false,
  });

  @override
  Widget build(BuildContext context) {
    final displayStr = isNegativeDisplay && cents > 0
        ? '- ${formatCurrency(cents, currency)}'
        : formatCurrency(cents, currency);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            displayStr,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

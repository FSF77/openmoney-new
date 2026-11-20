import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
import '../../services/cash_flow_engine.dart';
import '../../services/pdf_report_generator.dart';
import '../../store/money_store.dart';
import '../modals/account_multi_select_filter.dart';
import '../modals/category_drill_down_modal.dart';
import '../theme/liquid_glass.dart';

class ReportsView extends StatefulWidget {
  final MoneyStore store;
  const ReportsView({super.key, required this.store});

  @override
  State<ReportsView> createState() => _ReportsViewState();
}

class _ReportsViewState extends State<ReportsView> {
  Set<String> _selectedAccountIds = {};
  ReportPeriodKind _periodKind = ReportPeriodKind.monthly;
  CashFlowStatusFilter _statusFilter = CashFlowStatusFilter.all;
  String _tagFilter = 'all';
  late int _selectedYear;
  bool _mobileShowFilters = false;

  bool get _hasActiveFilters =>
      _selectedAccountIds.isNotEmpty ||
      _tagFilter != 'all' ||
      _statusFilter != CashFlowStatusFilter.all;

  @override
  void initState() {
    super.initState();
    _selectedYear = int.tryParse(widget.store.month.split('-')[0]) ?? DateTime.now().year;
  }

  void _showCategoryDrillDown(
    BuildContext context,
    String categoryPath,
    String periodKey,
    bool isAnnual,
  ) {
    showCategoryDrillDownModal(
      context,
      widget.store,
      categoryPath,
      initialCurrentMonthOnly: !isAnnual,
      targetMonth: isAnnual ? null : periodKey,
      targetYear: _selectedYear,
      isAnnual: isAnnual,
      titleOverride: isAnnual ? '$categoryPath · Ano $_selectedYear' : null,
      accountFilterIds:
          _selectedAccountIds.isEmpty ? null : _selectedAccountIds,
      statusFilter: _statusFilter,
      tagFilter: _tagFilter == 'all' ? null : _tagFilter,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final isAnnual = _periodKind == ReportPeriodKind.annual;
    final periodKey = isAnnual ? '$_selectedYear' : widget.store.month;
    final data = widget.store.buildMonthlyReport(
      periodKey,
      accountFilterIds:
          _selectedAccountIds.isEmpty ? null : _selectedAccountIds,
      isAnnual: isAnnual,
      statusFilter: _statusFilter,
      tagFilter: _tagFilter == 'all' ? null : _tagFilter,
    );

    final cur = data.currency;
    final baseCur = widget.store.baseCurrency;
    final isForeign = cur != baseCur;
    final rateInfo = isForeign ? widget.store.rateInfoFor(cur) : null;
    final curMeta = currencyMetaFor(cur);
    final isMobile = MediaQuery.sizeOf(context).width < 720;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 12 : 16,
        isMobile ? 10 : 14,
        isMobile ? 12 : 16,
        24,
      ),
      children: [
        GlassCard(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 12 : 16,
            vertical: isMobile ? 10 : 14,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Linha 1: Título, Filtro Mobile e Exportação PDF
              Row(
                children: [
                  Icon(Icons.pie_chart_outline, color: colors.accent, size: isMobile ? 22 : 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isAnnual
                              ? 'Relatório Anual $_selectedYear'
                              : 'Relatório',
                          style: TextStyle(
                            fontSize: isMobile ? 16.5 : 18,
                            fontWeight: FontWeight.w800,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          'Moeda: ${curMeta.flag} $cur${isForeign ? " (Base: $baseCur${rateInfo != null ? " • ${formatRateDate(rateInfo.updatedAt)}" : ""})" : ""}',
                          style: TextStyle(
                            fontSize: isMobile ? 11.5 : 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isMobile) ...[
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Filtros e Parâmetros',
                      icon: Icon(
                        _mobileShowFilters ? Icons.expand_less : Icons.tune,
                        size: 20,
                        color: (_mobileShowFilters || _hasActiveFilters)
                            ? colors.accent
                            : colors.textSecondary,
                      ),
                      onPressed: () => setState(
                          () => _mobileShowFilters = !_mobileShowFilters),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Tooltip(
                    message:
                        isAnnual ? 'Exportar PDF Anual' : 'Exportar PDF A4',
                    child: OutlinedButton(
                      style: isMobile
                          ? OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              minimumSize: const Size(36, 34),
                            )
                          : null,
                      onPressed: () {
                        final pdfBytes =
                            PdfReportGenerator.buildMonthlyReportPdfBytes(
                          store: widget.store,
                          monthYM: periodKey,
                          data: data,
                        );
                        PdfReportGenerator.saveAndOpenPdfBytes(
                          context,
                          pdfBytes: pdfBytes,
                          defaultFileName: isAnnual
                              ? 'Relatorio-Ano-$_selectedYear.pdf'
                              : 'Relatorio-${widget.store.month}.pdf',
                        );
                      },
                      child: const Icon(Icons.picture_as_pdf, size: 17),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Divider(height: 1, color: colors.borderGlass),
              const SizedBox(height: 10),
              // Linha 2: Período e Filtros
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<ReportPeriodKind>(
                    style: const ButtonStyle(
                      textStyle: WidgetStatePropertyAll(
                        TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: const [
                      ButtonSegment(
                          value: ReportPeriodKind.monthly,
                          label: Text('Mês')),
                      ButtonSegment(
                          value: ReportPeriodKind.annual,
                          label: Text('Ano')),
                    ],
                    selected: {_periodKind},
                    onSelectionChanged: (s) =>
                        setState(() => _periodKind = s.first),
                  ),
                  if (!isAnnual)
                    MonthYearPickerBar(
                      currentMonthYM: widget.store.month,
                      availableYears: widget.store.allYearsInDatabase(),
                      onMonthChanged: (ym) => widget.store.month = ym,
                    )
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          icon: const Icon(Icons.chevron_left),
                          tooltip: 'Ano anterior',
                          onPressed: () => setState(() => _selectedYear--),
                        ),
                        Text(
                          '$_selectedYear',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          icon: const Icon(Icons.chevron_right),
                          tooltip: 'Próximo ano',
                          onPressed: () => setState(() => _selectedYear++),
                        ),
                        const SizedBox(width: 4),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            textStyle: const TextStyle(fontSize: 12),
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: () => setState(
                              () => _selectedYear = DateTime.now().year),
                          child: const Text('Atual'),
                        ),
                      ],
                    ),
                ],
              ),
              if (isMobile && !_mobileShowFilters && _hasActiveFilters) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: colors.accent.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.filter_alt, size: 13, color: colors.accent),
                      const SizedBox(width: 4),
                      Text(
                        'Filtros aplicados',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => setState(() {
                          _selectedAccountIds.clear();
                          _tagFilter = 'all';
                          _statusFilter = CashFlowStatusFilter.all;
                        }),
                        child: Text(
                          'Limpar',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.accent,
                            fontWeight: FontWeight.w800,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (!isMobile || _mobileShowFilters) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AccountMultiSelectFilter(
                      store: widget.store,
                      selectedAccountIds: _selectedAccountIds,
                      asFormField: true,
                      width: isMobile ? 160 : 200,
                      onSelectionChanged: (set) =>
                          setState(() => _selectedAccountIds = set),
                    ),
                    Builder(
                      builder: (context) {
                        final tags = widget.store.allTags;
                        final effectiveTag = (_tagFilter == 'all' ||
                                _tagFilter == '__untagged__' ||
                                tags.any((t) =>
                                    t.toLowerCase() == _tagFilter.toLowerCase()))
                            ? _tagFilter
                            : 'all';
                        return SizedBox(
                          width: isMobile ? 135 : 155,
                          child: DropdownButtonFormField<String>(
                            initialValue: effectiveTag,
                            isExpanded: true,
                            isDense: true,
                            dropdownColor: colors.surfaceCard,
                            style: TextStyle(
                                fontSize: 12.5, color: colors.textPrimary),
                            decoration: InputDecoration(
                              labelText: 'Tag',
                              labelStyle: TextStyle(
                                  fontSize: 11, color: colors.textMuted),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: colors.borderGlass),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: colors.borderGlass),
                              ),
                            ),
                            items: [
                              const DropdownMenuItem(
                                  value: 'all', child: Text('Todas')),
                              const DropdownMenuItem(
                                  value: '__untagged__',
                                  child: Text('Sem tag')),
                              ...tags.map(
                                (t) => DropdownMenuItem(
                                  value: t,
                                  child: Text('#$t',
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ),
                            ],
                            onChanged: (v) {
                              if (v != null) setState(() => _tagFilter = v);
                            },
                          ),
                        );
                      },
                    ),
                    SizedBox(
                      width: isMobile ? 170 : 200,
                      child: DropdownButtonFormField<CashFlowStatusFilter>(
                        initialValue: _statusFilter,
                        isExpanded: true,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: colors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Status de Conciliação',
                          labelStyle: TextStyle(fontSize: 11, color: colors.textMuted),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: colors.borderGlass),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: colors.borderGlass),
                          ),
                        ),
                        items: CashFlowStatusFilter.values
                            .map((s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(
                                    s.shortLabel,
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _statusFilter = v);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        // KPI Cards
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 780;
            final cardWidth = isWide
                ? (constraints.maxWidth - 36) / 4
                : (constraints.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: KpiMetricCard(
                    label: isAnnual ? 'Receitas do Ano' : 'Receitas do Mês',
                    value: formatCurrency(data.totalIncome, cur),
                    subtitle: isForeign
                        ? '≈ ${formatCurrency(data.totalIncomeInBase ?? widget.store.convertToBase(data.totalIncome, cur), baseCur)}'
                        : null,
                    valueColor: colors.income,
                    icon: Icons.trending_up,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: KpiMetricCard(
                    label: isAnnual ? 'Despesas do Ano' : 'Despesas do Mês',
                    value: formatCurrency(data.totalExpense, cur),
                    subtitle: isForeign
                        ? '≈ ${formatCurrency(data.totalExpenseInBase ?? widget.store.convertToBase(data.totalExpense, cur), baseCur)}'
                        : null,
                    valueColor: colors.expense,
                    icon: Icons.trending_down,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: KpiMetricCard(
                    label: isAnnual ? 'Saldo do Ano' : 'Resultado Líquido',
                    value: formatCurrency(data.netTotal, cur),
                    subtitle: isForeign
                        ? '≈ ${formatCurrency(data.netTotalInBase ?? widget.store.convertToBase(data.netTotal, cur), baseCur)}'
                        : null,
                    valueColor:
                        data.netTotal >= 0 ? colors.income : colors.expense,
                    icon: Icons.account_balance_outlined,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: KpiMetricCard(
                    label: 'Taxa de Poupança',
                    value: '${data.savingsRate}%',
                    valueColor: colors.accent,
                    icon: Icons.savings_outlined,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 820;
            final colWidth = isWide
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: colWidth,
                  child: _buildCategorySectionCard(
                    context: context,
                    title: 'Receitas por Categoria',
                    groups: data.incomeGroups,
                    grandTotal: data.totalIncome,
                    currency: cur,
                    barColor: colors.income,
                    colors: colors,
                    periodKey: periodKey,
                    isAnnual: isAnnual,
                  ),
                ),
                SizedBox(
                  width: colWidth,
                  child: _buildCategorySectionCard(
                    context: context,
                    title: 'Despesas por Categoria',
                    groups: data.expenseGroups,
                    grandTotal: data.totalExpense,
                    currency: cur,
                    barColor: colors.expense,
                    colors: colors,
                    periodKey: periodKey,
                    isAnnual: isAnnual,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildCategorySectionCard({
    required BuildContext context,
    required String title,
    required List<CategoryGroupStat> groups,
    required int grandTotal,
    required String currency,
    required Color barColor,
    required OpenMoneyColors colors,
    required String periodKey,
    required bool isAnnual,
  }) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
              ),
              Text(
                formatCurrency(grandTotal, currency),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: barColor,
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          if (groups.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Sem movimentações neste período.',
                  style: TextStyle(color: colors.textSecondary),
                ),
              ),
            ),
          ...groups.map((g) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _showCategoryDrillDown(
                          context, g.name, periodKey, isAnnual),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          g.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13.5,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Icon(
                                        Icons.open_in_new,
                                        size: 13,
                                        color: colors.accent,
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${g.percentage}% • ${formatCurrency(g.total, currency)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: barColor,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: (g.percentage / 100.0).clamp(0.0, 1.0),
                                minHeight: 6,
                                backgroundColor: colors.borderGlass,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(barColor),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (g.subs.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    ...g.subs.map((sub) {
                      final fullPath = '${g.name}$kCategorySep${sub.name}';
                      return MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _showCategoryDrillDown(
                            context,
                            fullPath,
                            periodKey,
                            isAnnual,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 2.5, 4, 2.5),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          '↳ ${sub.name}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: colors.textSecondary,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.open_in_new,
                                        size: 11,
                                        color: colors.accent,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${sub.percentage}% • ${formatCurrency(sub.amount, currency)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: colors.textSecondary,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

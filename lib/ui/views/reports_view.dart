import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
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

  void _showCategoryDrillDown(
    BuildContext context,
    String categoryPath,
    String monthYM,
  ) {
    showCategoryDrillDownModal(
      context,
      widget.store,
      categoryPath,
      initialCurrentMonthOnly: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final data = widget.store.buildMonthlyReport(
      widget.store.month,
      accountFilterIds:
          _selectedAccountIds.isEmpty ? null : _selectedAccountIds,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.pie_chart_outline, color: colors.accent, size: 22),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Relatório Analítico Mensal',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                      ),
                      Text(
                        'Ignora estritamente transferências entre contas • Clique em qualquer categoria para auditar',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Wrap(
                spacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AccountMultiSelectFilter(
                    store: widget.store,
                    selectedAccountIds: _selectedAccountIds,
                    onSelectionChanged: (set) =>
                        setState(() => _selectedAccountIds = set),
                  ),
                  MonthYearPickerBar(
                    currentMonthYM: widget.store.month,
                    availableYears: widget.store.allYearsInDatabase(),
                    onMonthChanged: (ym) => widget.store.month = ym,
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.picture_as_pdf, size: 16),
                    label: const Text('Exportar PDF A4'),
                    onPressed: () {
                      final pdfBytes =
                          PdfReportGenerator.buildMonthlyReportPdfBytes(
                        store: widget.store,
                        monthYM: widget.store.month,
                        data: data,
                      );
                      PdfReportGenerator.saveAndOpenPdfBytes(
                        context,
                        pdfBytes: pdfBytes,
                        defaultFileName: 'Relatorio-${widget.store.month}.pdf',
                      );
                    },
                  ),
                ],
              ),
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
                    label: 'Receitas do Mês',
                    value: brl(data.totalIncome),
                    valueColor: colors.income,
                    icon: Icons.trending_up,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: KpiMetricCard(
                    label: 'Despesas do Mês',
                    value: brl(data.totalExpense),
                    valueColor: colors.expense,
                    icon: Icons.trending_down,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: KpiMetricCard(
                    label: 'Resultado Líquido',
                    value: brl(data.netTotal),
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
                    subtitle: 'Renda poupada no mês',
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
                    barColor: colors.income,
                    colors: colors,
                  ),
                ),
                SizedBox(
                  width: colWidth,
                  child: _buildCategorySectionCard(
                    context: context,
                    title: 'Despesas por Categoria',
                    groups: data.expenseGroups,
                    grandTotal: data.totalExpense,
                    barColor: colors.expense,
                    colors: colors,
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
    required Color barColor,
    required OpenMoneyColors colors,
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
                brl(grandTotal),
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
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _showCategoryDrillDown(
                          context, g.name, widget.store.month),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
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
                                  '${g.percentage}% • ${brl(g.total)}',
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
                    const SizedBox(height: 6),
                    ...g.subs.map((sub) {
                      final fullPath = '${g.name}$kCategorySep${sub.name}';
                      return MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _showCategoryDrillDown(
                            context,
                            fullPath,
                            widget.store.month,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '↳ ${sub.name}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colors.textSecondary,
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
                                Text(
                                  '${sub.percentage}% • ${brl(sub.amount)}',
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

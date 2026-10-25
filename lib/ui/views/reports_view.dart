import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
import '../../store/money_store.dart';
import '../modals/transaction_modal.dart';
import '../theme/liquid_glass.dart';

class ReportsView extends StatelessWidget {
  final MoneyStore store;
  const ReportsView({super.key, required this.store});

  void _showCategoryDrillDown(
    BuildContext context,
    String categoryPath,
    String monthYM,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    bool filterCurrentMonthOnly = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final affected = store.affectedCategoryPaths(categoryPath);
          final txs = store.db.txs.where((t) {
            if (!affected.contains(t.cat) && t.cat != categoryPath) {
              return false;
            }
            if (filterCurrentMonthOnly && !t.date.startsWith(monthYM)) {
              return false;
            }
            return true;
          }).toList()
            ..sort((a, b) => b.date.compareTo(a.date));

          final totalCents = txs.fold<int>(0, (s, t) => s + t.amt);

          return AlertDialog(
            backgroundColor: colors.bgSecondary,
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Auditoria de Categoria: $categoryPath',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: true,
                      label: Text(fmtMonth(monthYM)),
                    ),
                    const ButtonSegment(
                      value: false,
                      label: Text('Todo o Histórico'),
                    ),
                  ],
                  selected: {filterCurrentMonthOnly},
                  onSelectionChanged: (s) =>
                      setModalState(() => filterCurrentMonthOnly = s.first),
                ),
              ],
            ),
            content: SizedBox(
              width: 680,
              height: 440,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${txs.length} lançamento(s) • Total: ${brl(totalCents)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: colors.textSecondary,
                    ),
                  ),
                  const Divider(height: 18),
                  Expanded(
                    child: txs.isEmpty
                        ? const Center(
                            child: Text('Nenhum lançamento encontrado.'),
                          )
                        : ListView.separated(
                            itemCount: txs.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final t = txs[i];
                              final accName =
                                  store.accById(t.acc)?.name ?? 'Conta';
                              return ListTile(
                                dense: true,
                                title: Text(
                                  t.payee,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  '${fmtDate(t.date)} • $accName • ${t.cat}${t.memo.isNotEmpty ? " • ${t.memo}" : ""}',
                                ),
                                trailing: Text(
                                  brl(t.amt),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: t.amt >= 0
                                        ? colors.income
                                        : colors.expense,
                                  ),
                                ),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  showTransactionEditModal(context, store, t);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Fechar'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final data = store.buildMonthlyReport(store.month);

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
              MonthYearPickerBar(
                currentMonthYM: store.month,
                availableYears: store.allYearsInDatabase(),
                onMonthChanged: (ym) => store.month = ym,
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
                    title: 'Despesas por Categoria',
                    groups: data.expenseGroups,
                    grandTotal: data.totalExpense,
                    barColor: colors.expense,
                    colors: colors,
                  ),
                ),
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
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () =>
                        _showCategoryDrillDown(context, g.name, store.month),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  g.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                  ),
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
                  if (g.subs.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    ...g.subs.map((sub) {
                      final fullPath = '${g.name}$kCategorySep${sub.name}';
                      return InkWell(
                        onTap: () => _showCategoryDrillDown(
                          context,
                          fullPath,
                          store.month,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 3, 4, 3),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '↳ ${sub.name}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.textSecondary,
                                ),
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

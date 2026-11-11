import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';

class BudgetView extends StatelessWidget {
  final MoneyStore store;
  const BudgetView({super.key, required this.store});

  void _editBudget(
    BuildContext context,
    String categoryPath,
    int currentBudgetCents,
  ) {
    final baseCur = store.baseCurrency;
    final meta = currencyMetaFor(baseCur);
    final ctrl = TextEditingController(
      text: currentBudgetCents > 0 ? formatInputCents(currentBudgetCents) : '',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Limite de Gastos — $categoryPath'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Limite Mensal (${meta.symbol}) — Deixe 0 para remover',
            prefixText: '${meta.symbol} ',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final cents = (parseCents(ctrl.text) ?? 0).abs();
              store.setBudget(categoryPath, cents);
              Navigator.pop(ctx);
            },
            child: const Text('Salvar Limite'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);

    final monthTxs = store.monthTransactions(store.month).where((t) {
      return t.amt < 0 &&
          t.xfer == null &&
          t.peer == null &&
          t.auto != true &&
          store.isCategoryIncludedInReports(t.cat);
    }).toList();

    final baseCur = store.baseCurrency;
    final spentByPath = <String, int>{};
    for (final t in monthTxs) {
      final convAbs = store.convertTxToCurrency(t, baseCur).abs();
      spentByPath[t.cat] = (spentByPath[t.cat] ?? 0) + convAbs;
    }

    final topExpenseCats = store
        .topCategories(type: 'Despesa')
        .where((top) => store.isCategoryIncludedInReports(top.path))
        .toList();

    int totalPlanned = 0;
    int totalSpent = 0;

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
                  Icon(Icons.track_changes, color: colors.accent, size: 22),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Planejamento Financeiro: Limite de Gastos',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                      ),
                      Text(
                        'Clique em qualquer categoria ou subcategoria para definir seu teto mensal',
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
        ...topExpenseCats.map((top) {
          final subs = store
              .subCategories(top.name, type: 'Despesa')
              .where((sub) => store.isCategoryIncludedInReports(sub.path))
              .toList();
          int topBudget = store.db.budgets[top.path] ?? 0;
          int topSpent = spentByPath[top.path] ?? 0;

          int childrenBudgetSum = 0;
          int childrenSpentSum = 0;
          for (final sub in subs) {
            childrenBudgetSum += store.db.budgets[sub.path] ?? 0;
            childrenSpentSum += spentByPath[sub.path] ?? 0;
          }

          final effectiveTopBudget =
              topBudget > 0 ? topBudget : childrenBudgetSum;
          final effectiveTopSpent = topSpent + childrenSpentSum;

          totalPlanned += effectiveTopBudget;
          totalSpent += effectiveTopSpent;

          final isOver = effectiveTopBudget > 0 &&
              effectiveTopSpent > effectiveTopBudget;
          final ratio = effectiveTopBudget > 0
              ? (effectiveTopSpent / effectiveTopBudget).clamp(0.0, 1.0)
              : 0.0;

          return GlassCard(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => _editBudget(context, top.path, topBudget),
                  child: SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              top.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            if (isOver)
                              StatusBadge(
                                text: 'ACIMA DO LIMITE',
                                color: colors.expense,
                              ),
                          ],
                        ),
                        Text(
                          'Realizado: ${formatCurrency(effectiveTopSpent, baseCur)} / Limite: ${formatCurrency(effectiveTopBudget, baseCur)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                            color: isOver ? colors.expense : colors.textPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 7,
                    backgroundColor: colors.borderGlass,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isOver ? colors.expense : colors.accent,
                    ),
                  ),
                ),
                if (subs.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ...subs.map((sub) {
                    final sb = store.db.budgets[sub.path] ?? 0;
                    final ss = spentByPath[sub.path] ?? 0;
                    final subOver = sb > 0 && ss > sb;
                    final subRatio =
                        sb > 0 ? (ss / sb).clamp(0.0, 1.0) : 0.0;
                    return InkWell(
                      onTap: () => _editBudget(context, sub.path, sb),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        '↳ ${sub.name}',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w500,
                                          color: colors.textSecondary,
                                        ),
                                      ),
                                      if (subOver)
                                        StatusBadge(
                                          text: 'ACIMA DO LIMITE',
                                          color: colors.expense,
                                        ),
                                    ],
                                  ),
                                  Text(
                                    '${formatCurrency(ss, baseCur)} / ${sb > 0 ? formatCurrency(sb, baseCur) : "Definir limite"}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: subOver
                                          ? colors.expense
                                          : colors.textSecondary,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 5),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: subRatio,
                                minHeight: 5,
                                backgroundColor: colors.borderGlass,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  subOver
                                      ? colors.expense
                                      : colors.accent.withValues(alpha: 0.85),
                                ),
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
        const SizedBox(height: 8),
        GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 6,
              children: [
                const Text(
                  'Consolidado do Mês (Limite Total vs. Realizado)',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
                Text(
                  'Realizado: ${formatCurrency(totalSpent, baseCur)} • Limite: ${formatCurrency(totalPlanned, baseCur)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: totalPlanned > 0 && totalSpent > totalPlanned
                        ? colors.expense
                        : colors.income,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

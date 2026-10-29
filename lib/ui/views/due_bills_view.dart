import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';
import '../modals/account_multi_select_filter.dart';
import '../widgets/csv_export.dart';

class DueBillsView extends StatefulWidget {
  final MoneyStore store;
  const DueBillsView({super.key, required this.store});

  @override
  State<DueBillsView> createState() => _DueBillsViewState();
}

class _DueBillsViewState extends State<DueBillsView> {
  Set<String> _selectedAccountIds = {};

  MoneyStore get store => widget.store;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final ids = _selectedAccountIds;
    final items = store.dueBillItems(accountIds: ids);
    final summary = store.dueBillsSummary(accountIds: ids);

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
                  Icon(
                    Icons.notifications_active_outlined,
                    color: colors.accent,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Contas a Pagar e Receber (Vencimentos & Conciliação)',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                      ),
                      Text(
                        'Monitoramento de lançamentos não conciliados atrasados, vencendo hoje e nos próximos ${store.reminderDaysAhead} dias',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 195,
                    child: DropdownButtonFormField<int>(
                      initialValue: const [1, 2, 3, 5, 7, 10, 15, 30]
                              .contains(store.reminderDaysAhead)
                          ? store.reminderDaysAhead
                          : 3,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Antecedência',
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(),
                      ),
                      items: const [1, 2, 3, 5, 7, 10, 15, 30]
                          .map((d) => DropdownMenuItem(
                                value: d,
                                child: Text('$d dia(s) à frente'),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) store.setReminderDaysAhead(v);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  AccountMultiSelectFilter(
                    store: store,
                    selectedAccountIds: _selectedAccountIds,
                    onSelectionChanged: (set) =>
                        setState(() => _selectedAccountIds = set),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.download, size: 17),
                    label: const Text('Exportar CSV'),
                    onPressed: items.isEmpty
                        ? null
                        : () => exportCsvWithFeedback(
                              context,
                              csv: store.dueBillsCSVString(items),
                              defaultName:
                                  'openmoney-contas-a-pagar-receber.csv',
                              title: 'Exportar Contas a Pagar e Receber (CSV)',
                            ),
                  ),
                  const SizedBox(width: 10),
                  if (items.isNotEmpty)
                    FilledButton.icon(
                      icon: const Icon(Icons.done_all, size: 17),
                      label: Text('Conciliar Todos (${items.length})'),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Conciliar em Lote'),
                            content: Text(
                              'Confirma a conciliação de todos os ${items.length} lançamentos na janela de ${store.reminderDaysAhead} dia(s)?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Cancelar'),
                              ),
                              FilledButton(
                                onPressed: () {
                                  store.reconcileAllDueBills(
                                    accountIds: ids,
                                  );
                                  Navigator.pop(ctx);
                                },
                                child: const Text('Conciliar Todos'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 780;
            final cardW = isWide
                ? (constraints.maxWidth - 36) / 4
                : (constraints.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: cardW,
                  child: KpiMetricCard(
                    label: 'Contas a Pagar (${summary.payCount})',
                    value: brl(summary.payTotal),
                    valueColor: colors.expense,
                    icon: Icons.call_made,
                  ),
                ),
                SizedBox(
                  width: cardW,
                  child: KpiMetricCard(
                    label: 'Contas a Receber (${summary.receiveCount})',
                    value: brl(summary.receiveTotal),
                    valueColor: colors.income,
                    icon: Icons.call_received,
                  ),
                ),
                SizedBox(
                  width: cardW,
                  child: KpiMetricCard(
                    label: 'Saldo Líquido Projetado',
                    value: brl(summary.netTotal),
                    valueColor:
                        summary.netTotal >= 0 ? colors.income : colors.expense,
                    icon: Icons.balance,
                  ),
                ),
                SizedBox(
                  width: cardW,
                  child: KpiMetricCard(
                    label: 'Urgência (Atraso / Hoje)',
                    value:
                        '${summary.overdueCount} atraso • ${summary.dueTodayCount} hoje',
                    valueColor: summary.overdueCount > 0
                        ? colors.expense
                        : colors.warning,
                    icon: Icons.warning_amber_rounded,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        if (items.isEmpty)
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 42),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.verified_outlined, size: 42, color: colors.income),
                  const SizedBox(height: 10),
                  const Text(
                    'Tudo em dia! Nenhum lançamento pendente de conciliação nesta janela.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ...items.map((item) {
          final Color badgeColor = item.isOverdue
              ? colors.expense
              : (item.isDueToday ? colors.warning : colors.accent);
          final String badgeLabel = item.isOverdue
              ? 'ATRASADO (${item.daysUntilDue.abs()}D)'
              : (item.isDueToday
                  ? 'VENCE HOJE'
                  : 'EM ${item.daysUntilDue} DIAS');

          return GlassCard(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Conciliar com 1 clique',
                  icon: Icon(
                    Icons.radio_button_unchecked,
                    color: badgeColor,
                  ),
                  onPressed: () => store.toggleReconciled(item.tx.id),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          StatusBadge(text: badgeLabel, color: badgeColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.tx.payee,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        (item.dueDate != null && item.dueDate != item.tx.date)
                            ? 'Venc: ${fmtDate(item.effectiveDueDate)} (Compra: ${fmtDate(item.tx.date)}) • ${item.accountName} • ${item.tx.cat}'
                            : '${fmtDate(item.effectiveDueDate)} • ${item.accountName} • ${item.tx.cat}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  brl(item.tx.amt),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: item.tx.amt >= 0 ? colors.income : colors.expense,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () => store.navigateToTransaction(item.tx),
                  child: const Text('Ver'),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

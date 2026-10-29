import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';
import '../modals/account_multi_select_filter.dart';
import '../widgets/csv_export.dart';

class InstallmentsView extends StatefulWidget {
  final MoneyStore store;
  const InstallmentsView({super.key, required this.store});

  @override
  State<InstallmentsView> createState() => _InstallmentsViewState();
}

class _InstallmentsViewState extends State<InstallmentsView> {
  Set<String> _selectedAccountIds = {};

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final items = store.installmentItems(accountIds: _selectedAccountIds);
    final total = items.fold<int>(0, (s, i) => s + i.tx.amt.abs());
    final purchases = items
        .map((i) => '${i.tx.acc}|${i.tx.payee}|${i.tx.pt}')
        .toSet()
        .length;
    final next = items.isEmpty ? null : items.first;

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
                  Icon(Icons.credit_score, color: colors.accent, size: 22),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Compras Parceladas',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                      ),
                      Text(
                        'Despesas parceladas com parcelas em aberto',
                        style: TextStyle(
                            fontSize: 12, color: colors.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                              defaultName: 'openmoney-compras-parceladas.csv',
                              title: 'Exportar Compras Parceladas (CSV)',
                            ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, c) {
          final isWide = c.maxWidth >= 780;
          final w = isWide ? (c.maxWidth - 36) / 4 : (c.maxWidth - 12) / 2;
          return Wrap(spacing: 12, runSpacing: 12, children: [
            SizedBox(
              width: w,
              child: KpiMetricCard(
                label: 'Total em Aberto',
                value: brl(total),
                valueColor: colors.expense,
                icon: Icons.call_made,
              ),
            ),
            SizedBox(
              width: w,
              child: KpiMetricCard(
                label: 'Parcelas em Aberto',
                value: '${items.length}',
                valueColor: colors.accent,
                icon: Icons.format_list_numbered,
              ),
            ),
            SizedBox(
              width: w,
              child: KpiMetricCard(
                label: 'Compras Parceladas',
                value: '$purchases',
                valueColor: colors.accent,
                icon: Icons.shopping_bag_outlined,
              ),
            ),
            SizedBox(
              width: w,
              child: KpiMetricCard(
                label: 'Próxima Parcela',
                value: next == null
                    ? '—'
                    : '${fmtDate(next.effectiveDueDate)} • ${brl(next.tx.amt.abs())}',
                valueColor: colors.warning,
                icon: Icons.event,
              ),
            ),
          ]);
        }),
        const SizedBox(height: 14),
        if (items.isEmpty)
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 42),
            child: Center(
              child: Column(children: [
                Icon(Icons.verified_outlined, size: 42, color: colors.income),
                const SizedBox(height: 10),
                const Text(
                  'Nenhuma compra parcelada em aberto.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ]),
            ),
          ),
        ...items.map((item) {
          final badgeColor = item.isOverdue
              ? colors.expense
              : (item.isDueToday ? colors.warning : colors.accent);
          return GlassCard(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      StatusBadge(
                        text: 'PARCELA ${item.tx.pn ?? '?'}/${item.tx.pt}',
                        color: badgeColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.tx.payee,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 14),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                      'Venc: ${fmtDate(item.effectiveDueDate)} • ${item.accountName} • ${item.tx.cat}',
                      style:
                          TextStyle(fontSize: 12, color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
              Text(
                brl(item.tx.amt),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: colors.expense,
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () => store.navigateToTransaction(item.tx),
                child: const Text('Ver'),
              ),
            ]),
          );
        }),
      ],
    );
  }
}

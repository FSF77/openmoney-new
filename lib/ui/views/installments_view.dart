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
    final targetCur = store.targetCurrencyForAccounts(
        _selectedAccountIds.isEmpty ? null : _selectedAccountIds);
    final total = items.fold<int>(
        0,
        (s, i) =>
            s + store.convertTxToCurrency(i.tx, targetCur).abs());
    final purchases = items
        .map((i) => '${i.tx.acc}|${i.tx.payee}|${i.tx.pt}')
        .toSet()
        .length;
    final next = items.isEmpty ? null : items.first;
    final nextCur = next == null
        ? targetCur
        : (store.accById(next.tx.acc)?.effectiveCurrency ?? store.baseCurrency);

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
            vertical: isMobile ? 10 : 12,
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.credit_score, color: colors.accent, size: isMobile ? 20 : 22),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Compras Parceladas',
                          style: TextStyle(
                            fontSize: isMobile ? 16 : 18,
                            fontWeight: FontWeight.w800,
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          'Despesas parceladas com parcelas em aberto',
                          style: TextStyle(
                              fontSize: isMobile ? 11.5 : 12,
                              color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AccountMultiSelectFilter(
                    store: store,
                    selectedAccountIds: _selectedAccountIds,
                    onSelectionChanged: (set) =>
                        setState(() => _selectedAccountIds = set),
                  ),
                  Tooltip(
                    message: 'Exportar CSV',
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(38, 36),
                      ),
                      onPressed: items.isEmpty
                          ? null
                          : () => exportCsvWithFeedback(
                                context,
                                csv: store.dueBillsCSVString(items),
                                defaultName: 'openmoney-compras-parceladas.csv',
                                title: 'Exportar Compras Parceladas (CSV)',
                              ),
                      child: const Icon(Icons.download, size: 17),
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
                value: formatCurrency(total, targetCur),
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
                    : '${fmtDate(next.effectiveDueDate)} • ${formatCurrency(next.tx.amt.abs(), nextCur)}',
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
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 10 : 14,
              vertical: isMobile ? 8 : 10,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isMobile) ...[
                        Row(
                          children: [
                            StatusBadge(
                              text: 'PARCELA ${item.tx.pn ?? '?'}/${item.tx.pt}',
                              color: badgeColor,
                              fontSize: 9,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                item.accountName,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: colors.accent,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.tx.payee,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Venc: ${fmtDate(item.effectiveDueDate)}${item.tx.cat.isNotEmpty ? " • ${item.tx.cat}" : ""}',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ] else ...[
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
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        Text(
                          'Venc: ${fmtDate(item.effectiveDueDate)} • ${item.accountName} • ${item.tx.cat}',
                          style: TextStyle(
                              fontSize: 12, color: colors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      formatCurrency(
                        item.tx.amt,
                        store.accById(item.tx.acc)?.effectiveCurrency ??
                            store.baseCurrency,
                      ),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: isMobile ? 13 : 14,
                        color: colors.expense,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (isMobile) ...[
                      const SizedBox(height: 4),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 2),
                          minimumSize: const Size(0, 26),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => store.navigateToTransaction(item.tx),
                        child:
                            const Text('Ver', style: TextStyle(fontSize: 11.5)),
                      ),
                    ],
                  ],
                ),
                if (!isMobile) ...[
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: () => store.navigateToTransaction(item.tx),
                    child: const Text('Ver'),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }
}

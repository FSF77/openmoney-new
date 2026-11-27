import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
import '../../services/category_icon_registry.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';
import '../modals/account_multi_select_filter.dart';
import '../widgets/ai_assistant_drawer.dart';
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
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    final ids = _selectedAccountIds;
    final items = store.dueBillItems(accountIds: ids);
    final summary = store.dueBillsSummary(accountIds: ids);

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.notifications_active_outlined,
                    color: colors.accent,
                    size: isMobile ? 20 : 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isMobile
                              ? 'Contas a Pagar e Receber'
                              : 'Contas a Pagar e Receber (Vencimentos & Conciliação)',
                          style: TextStyle(
                            fontSize: isMobile ? 16 : 18,
                            fontWeight: FontWeight.w800,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Monitoramento de lançamentos não conciliados atrasados, vencendo hoje e nos próximos ${store.reminderDaysAhead} dias',
                          style: TextStyle(
                            fontSize: isMobile ? 11.5 : 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (store.isAiAssistantEnabled)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: Icon(
                        Icons.auto_awesome,
                        size: 15,
                        color: colors.accent,
                      ),
                      label: Text(
                        isMobile ? 'Recorrências IA' : 'Detectar Recorrências',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colors.accent,
                        ),
                      ),
                      onPressed: () {
                        const prompt =
                            'Identifique assinaturas e recorrências na minha base';
                        final isDesktop =
                            MediaQuery.of(context).size.width >= 860;
                        if (isDesktop) {
                          store.openAiAssistant(initialPrompt: prompt);
                        } else {
                          showAiAssistantModal(
                            context,
                            store,
                            initialPrompt: prompt,
                          );
                        }
                      },
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: isMobile ? 160 : 195,
                    child: DropdownButtonFormField<int>(
                      initialValue: const [1, 2, 3, 5, 7, 10, 15, 30]
                              .contains(store.reminderDaysAhead)
                          ? store.reminderDaysAhead
                          : 3,
                      isExpanded: true,
                      style: TextStyle(
                        fontSize: isMobile ? 12 : 13,
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
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
                                defaultName:
                                    'openmoney-contas-a-pagar-receber.csv',
                                title: 'Exportar Contas a Pagar e Receber (CSV)',
                              ),
                      child: const Icon(Icons.download, size: 17),
                    ),
                  ),
                  if (items.isNotEmpty)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      icon: const Icon(Icons.done_all, size: 16),
                      label: Text(
                        'Conciliar Todos (${items.length})',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
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
                    value: formatCurrency(summary.payTotal, summary.currency),
                    valueColor: colors.expense,
                    icon: Icons.call_made,
                  ),
                ),
                SizedBox(
                  width: cardW,
                  child: KpiMetricCard(
                    label: 'Contas a Receber (${summary.receiveCount})',
                    value: formatCurrency(summary.receiveTotal, summary.currency),
                    valueColor: colors.income,
                    icon: Icons.call_received,
                  ),
                ),
                SizedBox(
                  width: cardW,
                  child: KpiMetricCard(
                    label: 'Saldo Líquido Projetado',
                    value: formatCurrency(summary.netTotal, summary.currency),
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
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 10 : 14,
              vertical: isMobile ? 8 : 10,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  visualDensity: isMobile ? VisualDensity.compact : null,
                  padding: isMobile ? const EdgeInsets.all(4) : null,
                  constraints: isMobile ? const BoxConstraints() : null,
                  tooltip: 'Conciliar com 1 clique',
                  icon: Icon(
                    Icons.radio_button_unchecked,
                    color: badgeColor,
                    size: isMobile ? 20 : 22,
                  ),
                  onPressed: () => store.toggleReconciled(item.tx.id),
                ),
                SizedBox(width: isMobile ? 8 : 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isMobile) ...[
                        Row(
                          children: [
                            StatusBadge(
                              text: badgeLabel,
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
                        Row(
                          children: [
                            if (item.tx.cat.isNotEmpty) ...[
                              CategoryIconBadge(
                                store: store,
                                categoryPath: item.tx.cat,
                                fallbackType:
                                    item.tx.amt >= 0 ? 'Receita' : 'Despesa',
                                size: 16,
                                borderRadius: 4.5,
                              ),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                (item.dueDate != null && item.dueDate != item.tx.date)
                                    ? 'Venc: ${fmtDate(item.effectiveDueDate)} (Compra: ${fmtDate(item.tx.date)})${item.tx.cat.isNotEmpty ? " • ${item.tx.cat}" : ""}'
                                    : '${fmtDate(item.effectiveDueDate)}${item.tx.cat.isNotEmpty ? " • ${item.tx.cat}" : ""}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
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
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (item.tx.cat.isNotEmpty) ...[
                              CategoryIconBadge(
                                store: store,
                                categoryPath: item.tx.cat,
                                fallbackType:
                                    item.tx.amt >= 0 ? 'Receita' : 'Despesa',
                                size: 16,
                                borderRadius: 4.5,
                              ),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                (item.dueDate != null && item.dueDate != item.tx.date)
                                    ? 'Venc: ${fmtDate(item.effectiveDueDate)} (Compra: ${fmtDate(item.tx.date)}) • ${item.accountName} • ${item.tx.cat}'
                                    : '${fmtDate(item.effectiveDueDate)} • ${item.accountName} • ${item.tx.cat}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
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
                        color: item.tx.amt >= 0 ? colors.income : colors.expense,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (isMobile) ...[
                      const SizedBox(height: 4),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          minimumSize: const Size(0, 26),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => store.navigateToTransaction(item.tx),
                        child: const Text('Ver', style: TextStyle(fontSize: 11.5)),
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

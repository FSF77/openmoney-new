import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
import '../../services/cash_flow_engine.dart';
import '../../store/money_store.dart';

/// Abre o detalhe dos lançamentos que compõem uma célula do Fluxo de Caixa.
Future<void> showCashFlowDetailDialog(
  BuildContext context, {
  required MoneyStore store,
  required CashFlowMatrix matrix,
  int? columnIndex,
  bool? isIncome,
  String? top,
  String? sub,
  Set<String>? accountFilterIds,
  CashFlowStatusFilter statusFilter = CashFlowStatusFilter.all,
  CashFlowKindFilter kindFilter = CashFlowKindFilter.all,
  CashFlowDateMode dateMode = CashFlowDateMode.transactionDate,
  String searchQuery = '',
}) {
  final items = CashFlowEngine.detail(
    transactions: store.db.txs,
    accounts: store.db.accounts,
    columns: matrix.columns,
    columnIndex: columnIndex,
    isIncome: isIncome,
    top: top,
    sub: sub,
    accountFilterIds: accountFilterIds,
    statusFilter: statusFilter,
    kindFilter: kindFilter,
    dateMode: dateMode,
    searchQuery: searchQuery,
  );

  final parts = <String>[];
  if (top != null) {
    parts.add((sub != null && sub != CashFlowEngine.directSubKey)
        ? '$top › $sub'
        : top);
  } else if (isIncome != null) {
    parts.add(isIncome ? 'Rendimento' : 'Despesas');
  } else {
    parts.add('Todos os lançamentos');
  }
  parts.add(columnIndex != null && columnIndex < matrix.columns.length
      ? matrix.columns[columnIndex].title
      : 'Período todo');

  final total = items.fold<int>(0, (a, b) => a + b.tx.amt);
  final colors = Theme.of(context).colorScheme;

  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(parts.join(' · '), style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 720,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${items.length} lançamento(s)'
              '${dateMode == CashFlowDateMode.paymentDate ? ' · regime: pagamento da fatura' : ''}',
              style: const TextStyle(fontSize: 11.5),
            ),
            const Divider(),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('Nenhum lançamento encontrado.'))
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final it = items[i];
                        final amt = it.tx.amt;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 90,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(fmtDate(it.effectiveDate),
                                        style: const TextStyle(fontSize: 12)),
                                    if (it.effectiveDate != it.tx.date)
                                      Text('lanç. ${fmtDate(it.tx.date)}',
                                          style: const TextStyle(fontSize: 9.5)),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(it.tx.payee,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12.5)),
                                    Text(
                                      it.sub != null
                                          ? '${it.top} › ${it.sub}'
                                          : it.top,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: 130,
                                child: Text(it.accountName,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11.5)),
                              ),
                              Icon(
                                it.tx.rec
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                size: 14,
                                color: it.tx.rec ? Colors.green : Colors.grey,
                              ),
                              SizedBox(
                                width: 120,
                                child: Text(
                                  brl(amt),
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12.5,
                                    color: amt >= 0
                                        ? Colors.green.shade600
                                        : colors.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const Divider(),
            Row(
              children: [
                const Text('Total',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                const Spacer(),
                Text(
                  brl(total),
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: total >= 0 ? Colors.green.shade600 : colors.error,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );
}

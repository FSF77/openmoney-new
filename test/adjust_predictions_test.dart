import 'package:flutter_test/flutter_test.dart';
import 'package:openmoney/models/openmoney_models.dart';
import 'package:openmoney/store/money_store.dart';

void main() {
  test('abatimento por fatura considera apenas a mesma fatura do cartão', () {
    final store = MoneyStore(autoBoot: false);
    store.db = Database(
      accounts: [
        Account(id: 'bank', name: 'Banco', type: 'Corrente', opening: 0),
        Account(
          id: 'x',
          name: 'Cartão X',
          type: 'Cartão de crédito',
          opening: 0,
          card: CardConfig(closeDay: 25, dueDay: 5, pay: 'bank'),
        ),
      ],
      txs: [
        Transaction(acc: 'x', date: '2026-10-15', payee: 'Previsão Mercado', cat: 'Mercado', amt: -100000),
        Transaction(acc: 'bank', date: '2026-10-02', payee: 'Mercado', cat: 'Mercado', amt: -20000),
        Transaction(acc: 'x', date: '2026-10-15', payee: 'Mercado', cat: 'Mercado', amt: -10000),
        Transaction(acc: 'x', date: '2026-10-29', payee: 'Mercado', cat: 'Mercado', amt: -10000),
      ],
      predMode: 'invoice',
    );
    final res = store.adjustPredictions('2026-10');
    expect(res.totalDeductedCents, 10000);
    expect(store.db.txs.firstWhere((t) => t.payee.startsWith('Previs')).amt, -90000);
  });
}

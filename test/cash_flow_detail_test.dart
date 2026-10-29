import 'package:flutter_test/flutter_test.dart';
import 'package:openmoney/models/openmoney_models.dart';
import 'package:openmoney/services/cash_flow_engine.dart';

void main() {
  test('soma do detalhe bate com cada celula da matriz', () {
    final accounts = [
      Account(id: 'a', name: 'Banco', type: 'Corrente', opening: 0),
      Account(id: 'b', name: 'Banco 2', type: 'Corrente', opening: 0),
    ];
    final txs = [
      Transaction(acc: 'a', date: '2026-01-05', payee: 'M1', cat: 'Alimentação › Mercado', amt: -10000),
      Transaction(acc: 'a', date: '2026-01-20', payee: 'M2', cat: 'Alimentação', amt: -2500),
      Transaction(acc: 'a', date: '2026-02-03', payee: 'M3', cat: 'Alimentação › Mercado', amt: -7000),
      Transaction(acc: 'b', date: '2026-02-10', payee: 'Salário', cat: 'Salário', amt: 500000),
      Transaction(acc: 'a', date: '2026-02-11', payee: 'Xfer', cat: '', amt: -999, xfer: 'x', peer: 'b'),
    ];
    final m = CashFlowEngine.buildMatrix(
      transactions: txs,
      accounts: accounts,
      periodKind: CashFlowPeriodKind.monthly,
      year: 2026,
    );
    int sum(List<CashFlowDetailItem> l) => l.fold(0, (a, b) => a + b.tx.amt.abs());
    for (final entry in [(m.incomeSection, true), (m.expenseSection, false)]) {
      final sec = entry.$1;
      final inc = entry.$2;
      for (final g in sec.groups) {
        for (var i = 0; i < m.columns.length; i++) {
          final d = CashFlowEngine.detail(
              transactions: txs, accounts: accounts, columns: m.columns,
              columnIndex: i, isIncome: inc, top: g.name);
          expect(sum(d), g.periodTotals[i], reason: '${g.name} col $i');
        }
        for (final s in g.subcategories) {
          final key = s.name.endsWith(' - Não-atribuído') ? CashFlowEngine.directSubKey : s.name;
          final d = CashFlowEngine.detail(
              transactions: txs, accounts: accounts, columns: m.columns,
              isIncome: inc, top: g.name, sub: key);
          expect(sum(d), s.total, reason: s.name);
        }
      }
      final all = CashFlowEngine.detail(
          transactions: txs, accounts: accounts, columns: m.columns, isIncome: inc);
      expect(sum(all), sec.grandTotal);
    }
  });
}

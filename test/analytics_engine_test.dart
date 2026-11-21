import 'package:flutter_test/flutter_test.dart';
import 'package:openmoney/services/analytics_engine.dart';
import 'package:openmoney/store/money_store.dart';

void main() {
  group('AnalyticsEngine', () {
    late MoneyStore store;
    final now = DateTime(2026, 11, 15);

    setUp(() {
      store = MoneyStore(autoBoot: false);
      store.saveAccount(
        name: 'Conta Corrente',
        type: 'Corrente',
        openingCents: 100000,
        closeDay: 0,
        dueDay: 0,
        payAccId: '',
      );
      final acc = store.db.accounts.first;
      void tx(String d, String p, String c, int amt) => store.addTransaction(
            accId: acc.id,
            date: d,
            payee: p,
            catSelection: c,
            memo: '',
            signedAmt: amt,
          );
      tx('2026-10-05', 'Empresa', 'Salário', 500000);
      tx('2026-10-10', 'Mercado', 'Alimentação', -100000);
      tx('2026-11-05', 'Empresa', 'Salário', 500000);
      tx('2026-11-08', 'Mercado', 'Alimentação', -200000);
    });

    AnalyticsFilter f({String from = '2026-11', String to = '2026-11'}) =>
        AnalyticsFilter(fromYM: from, toYM: to);

    test('receita, despesa, resultado e poupança do mês', () {
      final s = AnalyticsEngine.compute(store, f(), now: now);
      expect(s.income, 500000);
      expect(s.expense, 200000);
      expect(s.net, 300000);
      expect(s.savingsRate, closeTo(0.6, 1e-9));
    });

    test('período anterior para comparação', () {
      final s = AnalyticsEngine.compute(store, f(), now: now);
      expect(s.prevIncome, 500000);
      expect(s.prevExpense, 100000);
    });

    test('categorias e filtro cruzado por categoria', () {
      final s = AnalyticsEngine.compute(store, f(), now: now);
      expect(s.byCategory.first.name, 'Alimentação');
      expect(s.byCategory.first.cents, 200000);
      final only = AnalyticsEngine.compute(
          store, f().copyWith(categoryTop: 'Salário'),
          now: now);
      expect(only.expense, 0);
      expect(only.income, 500000);
    });

    test('patrimônio acumulado mês a mês', () {
      final s = AnalyticsEngine.compute(
          store, f(from: '2026-10', to: '2026-11'),
          now: now);
      expect(s.monthly.length, 2);
      expect(s.monthly[0].netWorth, 100000 + 500000 - 100000);
      expect(s.monthly[1].netWorth, 100000 + 1000000 - 300000);
    });

    test('orçamento orçado × realizado', () {
      store.setBudget('Alimentação', 150000);
      final s = AnalyticsEngine.compute(store, f(), now: now);
      expect(s.budgets.length, 1);
      expect(s.budgets.first.spent, 200000);
      expect(s.budgets.first.ratio, greaterThan(1));
    });

    test('base vazia não gera divisão por zero', () {
      final empty = MoneyStore(autoBoot: false);
      final s = AnalyticsEngine.compute(empty, f(), now: now);
      expect(s.income, 0);
      expect(s.savingsRate, 0);
      expect(s.runwayMonths, 0);
      expect(s.healthScore, inInclusiveRange(0, 100));
    });

    test('addMonths atravessa virada de ano', () {
      expect(AnalyticsEngine.addMonths('2026-01', -1), '2025-12');
      expect(AnalyticsEngine.addMonths('2026-11', 3), '2027-02');
    });
  });
}

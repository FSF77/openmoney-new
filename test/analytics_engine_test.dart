import 'package:flutter_test/flutter_test.dart';
import 'package:openmoney/services/analytics_engine.dart';
import 'package:openmoney/services/cash_flow_engine.dart';
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
      store.saveAccount(
        name: 'Investimento CDB',
        type: 'Investimento',
        openingCents: 19900000, // R$ 199.000,00 de investimento
        closeDay: 0,
        dueDay: 0,
        payAccId: '',
      );
      final acc = store.db.accounts.first; // CC com 1.000,00 de abertura -> Total patrimônio = 200.000,00
      void tx(String d, String p, String c, int amt) => store.addTransaction(
            accId: acc.id,
            date: d,
            payee: p,
            catSelection: c,
            memo: '',
            signedAmt: amt,
          );
      tx('2026-10-05', 'Empresa', 'Salário', 500000);
      tx('2026-10-10', 'Mercado', 'Alimentação', -1000000); // R$ 10.000 de despesa em out
      tx('2026-11-05', 'Empresa', 'Salário', 500000);
      tx('2026-11-08', 'Mercado', 'Alimentação', -1000000); // R$ 10.000 de despesa em nov
    });

    AnalyticsFilter f({
      String from = '2026-11',
      String to = '2026-11',
      bool isAllTime = false,
      CashFlowStatusFilter statusFilter = CashFlowStatusFilter.all,
    }) =>
        AnalyticsFilter(
          fromYM: from,
          toYM: to,
          isAllTime: isAllTime,
          statusFilter: statusFilter,
        );

    test('receita, despesa, resultado e poupança batem com buildMonthlyReport', () {
      final s = AnalyticsEngine.compute(store, f(), now: now);
      final rep = store.buildMonthlyReport('2026-11');
      expect(s.income, rep.totalIncome);
      expect(s.expense, rep.totalExpense);
      expect(s.net, rep.netTotal);
      expect(s.income, 500000);
      expect(s.expense, 1000000);
      expect(s.net, -500000);
      expect(s.savingsRate, closeTo(-1.0, 1e-9));
    });

    test('filtro de status de conciliação filtra conciliados e não conciliados com precisão', () {
      final acc = store.db.accounts.first;
      // Adiciona uma despesa conciliada de R$ 300,00
      store.addTransaction(
        accId: acc.id,
        date: '2026-11-02',
        payee: 'Farmácia',
        catSelection: 'Saúde',
        memo: '',
        signedAmt: -30000,
      );
      // E uma despesa futura/não conciliada de R$ 700,00
      store.addTransaction(
        accId: acc.id,
        date: '2026-11-28', // futuro em relação a todayISO
        payee: 'Dentista',
        catSelection: 'Saúde',
        memo: '',
        signedAmt: -70000,
      );

      // Marca Farmácia como conciliada e Dentista como não conciliada
      final farmacia = store.db.txs.firstWhere((t) => t.payee == 'Farmácia');
      farmacia.rec = true;
      final dentista = store.db.txs.firstWhere((t) => t.payee == 'Dentista');
      dentista.rec = false;

      // Status: Todos
      final sAll = AnalyticsEngine.compute(store, f(statusFilter: CashFlowStatusFilter.all), now: now);
      final repAll = store.buildMonthlyReport('2026-11', statusFilter: CashFlowStatusFilter.all);
      expect(sAll.expense, repAll.totalExpense);

      // Status: Apenas conciliados
      final sRec = AnalyticsEngine.compute(store, f(statusFilter: CashFlowStatusFilter.reconciledOnly), now: now);
      final repRec = store.buildMonthlyReport('2026-11', statusFilter: CashFlowStatusFilter.reconciledOnly);
      expect(sRec.expense, repRec.totalExpense);
      expect(sRec.expense < sAll.expense, isTrue);

      // Status: Apenas não conciliados
      final sPend = AnalyticsEngine.compute(store, f(statusFilter: CashFlowStatusFilter.pendingOnly), now: now);
      final repPend = store.buildMonthlyReport('2026-11', statusFilter: CashFlowStatusFilter.pendingOnly);
      expect(sPend.expense, repPend.totalExpense);
      expect(sPend.expense + sRec.expense, sAll.expense);
    });

    test('reserva de emergência considera TODO o patrimônio (ex: R\$ 200.000 de patrimônio e R\$ 10.000 de despesa = 20 meses)', () {
      final s = AnalyticsEngine.compute(store, f(), now: now);
      expect(s.runwayMonths, closeTo(19.0, 0.1));

      // Ajustando o patrimônio para exatamente R$ 200.000:
      final acc = store.db.accounts.first;
      store.addTransaction(
        accId: acc.id,
        date: '2026-11-01',
        payee: 'Aporte',
        catSelection: 'Rendimentos',
        memo: '',
        signedAmt: 1000000, // + R$ 10.000 -> Total patrimônio = R$ 200.000
      );
      final s2 = AnalyticsEngine.compute(store, f(), now: now);
      expect(s2.netWorth, 20000000); // R$ 200.000,00
      expect(s2.runwayMonths, closeTo(20.0, 0.1)); // Exatamente 20.0 meses!
    });

    test('filtro Todo período engloba todos os meses sem quebrar', () {
      final s = AnalyticsEngine.compute(store, f(from: '2026-10', to: '2026-11', isAllTime: true), now: now);
      expect(s.income, 1000000); // 5000 + 5000
      expect(s.expense, 2000000); // 10000 + 10000
      expect(s.prevIncome, 0);
      expect(s.prevExpense, 0);
    });

    test('transferência entre contas não é contada como receita ou despesa', () {
      final acc1 = store.db.accounts[0];
      final acc2 = store.db.accounts[1];
      store.addTransaction(
        accId: acc1.id,
        date: '2026-11-10',
        payee: 'Transferência para CDB',
        catSelection: 'xfer:${acc2.id}',
        memo: '',
        signedAmt: -50000,
      );
      final s = AnalyticsEngine.compute(store, f(), now: now);
      final rep = store.buildMonthlyReport('2026-11');
      expect(s.expense, rep.totalExpense);
      expect(s.expense, 1000000); // Não aumentou a despesa
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

import 'package:flutter_test/flutter_test.dart';
import 'package:openmoney/models/openmoney_models.dart';
import 'package:openmoney/services/cash_flow_engine.dart';
import 'package:openmoney/store/money_store.dart';

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

  test('CashFlowKindFilter filtra parcelados e recorrentes e zera saldo inicial', () {
    final accounts = [
      Account(id: 'a', name: 'Banco', type: 'Corrente', opening: 100000),
    ];
    final txs = [
      Transaction(acc: 'a', date: '2026-01-05', payee: 'Parcelado 1', cat: 'Despesa', amt: -1000, pn: 1, pt: 3),
      Transaction(acc: 'a', date: '2026-01-10', payee: 'Recorrente 1', cat: 'Despesa', amt: -2000, recId: 'r1'),
      Transaction(acc: 'a', date: '2026-01-15', payee: 'Avulso', cat: 'Despesa', amt: -3000),
    ];

    final mAll = CashFlowEngine.buildMatrix(
      transactions: txs,
      accounts: accounts,
      periodKind: CashFlowPeriodKind.monthly,
      year: 2026,
      kindFilter: CashFlowKindFilter.all,
    );
    expect(mAll.expenseSection.grandTotal, 6000);
    expect(mAll.priorBalanceGrandTotal, 100000);

    final mInst = CashFlowEngine.buildMatrix(
      transactions: txs,
      accounts: accounts,
      periodKind: CashFlowPeriodKind.monthly,
      year: 2026,
      kindFilter: CashFlowKindFilter.installmentOnly,
    );
    expect(mInst.expenseSection.grandTotal, 1000);
    expect(mInst.priorBalanceGrandTotal, 0);

    final mRec = CashFlowEngine.buildMatrix(
      transactions: txs,
      accounts: accounts,
      periodKind: CashFlowPeriodKind.monthly,
      year: 2026,
      kindFilter: CashFlowKindFilter.recurringOnly,
    );
    expect(mRec.expenseSection.grandTotal, 2000);
    expect(mRec.priorBalanceGrandTotal, 0);
  });

  test('Visão Diária do Fluxo de Caixa gera colunas corretas para o mês', () {
    final accounts = [
      Account(
        id: 'a',
        name: 'Banco',
        type: 'Corrente',
        opening: 50000,
        bankCode: '341',
        agency: '0001',
        accountNumber: '12345-6',
        comments: 'Conta principal',
        minBalance: 10000,
      ),
    ];

    // Testa serialização dos novos campos da Account
    final json = accounts.first.toJson();
    expect(json['bankCode'], '341');
    expect(json['agency'], '0001');
    expect(json['accountNumber'], '12345-6');
    expect(json['comments'], 'Conta principal');
    expect(json['minBalance'], 10000);

    final fromJson = Account.fromJson(json);
    expect(fromJson.bankCode, '341');
    expect(fromJson.minBalance, 10000);

    // Testa matriz diária em Outubro (31 dias)
    final txs = [
      Transaction(acc: 'a', date: '2026-10-01', payee: 'T1', cat: 'Alimentação', amt: -1000),
      Transaction(acc: 'a', date: '2026-10-15', payee: 'T2', cat: 'Alimentação', amt: -2500),
      Transaction(acc: 'a', date: '2026-10-31', payee: 'T3', cat: 'Alimentação', amt: -3000),
    ];

    final mDaily = CashFlowEngine.buildMatrix(
      transactions: txs,
      accounts: accounts,
      periodKind: CashFlowPeriodKind.daily,
      year: 2026,
      month: 10,
    );

    expect(mDaily.columns.length, 31);
    expect(mDaily.columns.first.id, '2026-10-01');
    expect(mDaily.columns.last.id, '2026-10-31');
    expect(mDaily.expenseSection.grandTotal, 6500);

    // Testa restrição de no máximo 10 anos na visão anual
    final mYearly = CashFlowEngine.buildMatrix(
      transactions: [
        Transaction(acc: 'a', date: '1990-01-01', payee: 'Antigo', cat: 'X', amt: -100),
        Transaction(acc: 'a', date: '2026-05-01', payee: 'Atual', cat: 'X', amt: -200),
        Transaction(acc: 'a', date: '2040-01-01', payee: 'Distante', cat: 'X', amt: -300),
      ],
      accounts: accounts,
      periodKind: CashFlowPeriodKind.yearly,
      year: 2026,
    );

    final currentYear = DateTime.now().year;
    for (final col in mYearly.columns) {
      final y = int.parse(col.id);
      expect(y >= currentYear - 7 && y <= currentYear + 2, isTrue,
          reason: 'Ano $y fora da janela permitida');
    }
  });

  test('concilia saldo acumulado com conta de investimentos e saída fora de relatórios', () {
    final accounts = [
      Account(id: 'cc', name: 'Nubank', type: 'Corrente', opening: -500000),
      Account(
          id: 'inv',
          name: 'Corretora',
          type: 'Investimento',
          opening: 19400000),
    ];
    final txs = [
      Transaction(
        acc: 'inv',
        date: '2026-11-10',
        payee: 'Ajuste Posição Inicial',
        cat: 'Ajuste Carteira',
        amt: -19400000,
      ),
      Transaction(
        acc: 'cc',
        date: '2026-11-15',
        payee: 'Mercado',
        cat: 'Alimentação',
        amt: -10000,
      ),
    ];

    bool includeInCashFlow(String cat) => cat != 'Ajuste Carteira';

    // 1. Todas as contas: saída de ajuste não entra em Despesas e carteira entra no saldo acumulado
    final mAll = CashFlowEngine.buildMatrix(
      transactions: txs,
      accounts: accounts,
      periodKind: CashFlowPeriodKind.monthly,
      year: 2026,
      investmentMarketValueByAccount: {'inv': 19400889},
      isCategoryIncludedInCashFlow: includeInCashFlow,
    );

    expect(mAll.expenseSection.grandTotal, 10000);
    // Saldo inicial consolidado: -5.000 + (194.000 - 194.000 + 194.008,89) = +189.008,89
    expect(mAll.priorBalancePeriodTotals[10], 18900889);
    // Saldo final em Nov/2026: 189.008,89 - 100,00 = 188.908,89
    expect(mAll.endingBalancePeriodTotals[10], 18890889);

    // 2. Filtrando apenas conta Corrente: não soma carteira da corretora
    final mCcOnly = CashFlowEngine.buildMatrix(
      transactions: txs,
      accounts: accounts,
      periodKind: CashFlowPeriodKind.monthly,
      year: 2026,
      accountFilterIds: {'cc'},
      investmentMarketValueByAccount: {'inv': 19400889},
      isCategoryIncludedInCashFlow: includeInCashFlow,
    );
    expect(mCcOnly.priorBalancePeriodTotals[10], -500000);
    expect(mCcOnly.endingBalancePeriodTotals[10], -510000);

    // 3. Conta de investimento criada do zero (opening = 0) com carteira de R$ 50.000
    final mZeroOpen = CashFlowEngine.buildMatrix(
      transactions: const [],
      accounts: [
        Account(id: 'inv0', name: 'XP', type: 'Investimento', opening: 0),
      ],
      periodKind: CashFlowPeriodKind.monthly,
      year: 2026,
      investmentMarketValueByAccount: {'inv0': 5000000},
    );
    expect(mZeroOpen.priorBalanceGrandTotal, 5000000);
    expect(mZeroOpen.endingBalanceGrandTotal, 5000000);
  });

  test('CategoryItem e MoneyStore separam includeInReports de includeInCashFlow', () {
    final legacy = CategoryItem.fromJson({'name': 'Histórico', 'type': 'Despesa', 'includeInReports': false});
    expect(legacy.effectiveIncludeInReports, isFalse);
    expect(legacy.effectiveIncludeInCashFlow, isTrue);

    final excludedBoth = CategoryItem(
      name: 'Ajuste Carteira',
      type: 'Despesa',
      includeInReports: false,
      includeInCashFlow: false,
    );
    final roundtrip = CategoryItem.fromJson(excludedBoth.toJson());
    expect(roundtrip.includeInCashFlow, isFalse);
    expect(roundtrip.effectiveIncludeInCashFlow, isFalse);

    final store = MoneyStore(autoBoot: false);
    store.saveCategory(
      name: 'Histórico Antigo',
      type: 'Despesa',
      includeInReports: false,
      includeInCashFlow: true,
    );
    store.saveCategory(
      name: 'Ajuste Investimentos',
      type: 'Despesa',
      includeInReports: false,
      includeInCashFlow: false,
    );

    expect(store.isCategoryIncludedInReports('Histórico Antigo'), isFalse);
    expect(store.isCategoryIncludedInCashFlow('Histórico Antigo'), isTrue);
    expect(store.isCategoryIncludedInReports('Ajuste Investimentos'), isFalse);
    expect(store.isCategoryIncludedInCashFlow('Ajuste Investimentos'), isFalse);
  });
}

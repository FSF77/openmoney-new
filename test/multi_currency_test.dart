import 'package:flutter_test/flutter_test.dart';
import 'package:openmoney/models/openmoney_models.dart';
import 'package:openmoney/services/cash_flow_engine.dart';
import 'package:openmoney/services/currency_rate_service.dart';
import 'package:openmoney/services/importers_exporters.dart';
import 'package:openmoney/store/money_store.dart';

void main() {
  group('Multi-Moeda: Catálogo, Formatação e Triangulação', () {
    test('inclui todas as 11 moedas suportadas incluindo CAD e AUD', () {
      final codes = kSupportedCurrencies.map((c) => c.code).toSet();
      expect(
        codes,
        containsAll([
          'BRL',
          'USD',
          'EUR',
          'CAD',
          'AUD',
          'GBP',
          'PYG',
          'ARS',
          'UYU',
          'CHF',
          'CLP',
        ]),
      );
      expect(kSupportedCurrencies.length, 11);
      expect(currencyMetaFor('cad').symbol, r'C$');
      expect(currencyMetaFor('aud').symbol, r'A$');
      expect(currencyMetaFor('pyg').decimals, 0);
    });

    test('formatCurrency formata centavos nas diferentes moedas corretamente', () {
      expect(formatCurrency(125050, 'BRL'), r'R$ 1.250,50');
      expect(formatCurrency(-9900, 'USD'), r'-US$ 99,00');
      expect(formatCurrency(150000000, 'PYG'), '₲ 1.500.000');
      expect(formatCurrency(45075, 'CAD'), r'C$ 450,75');
      expect(formatCurrency(80025, 'AUD'), r'A$ 800,25');
    });

    test('exchangeRateBetween e convertCents triangulam corretamente via BRL', () {
      final rates = <String, CurrencyRateInfo>{
        'USD': const CurrencyRateInfo(
          rate: 5.0,
          updatedAt: '2026-11-10T10:00:00Z',
        ),
        'EUR': const CurrencyRateInfo(
          rate: 6.0,
          updatedAt: '2026-11-10T10:00:00Z',
        ),
        'CAD': const CurrencyRateInfo(
          rate: 4.0,
          updatedAt: '2026-11-10T10:00:00Z',
        ),
        'AUD': const CurrencyRateInfo(
          rate: 3.5,
          updatedAt: '2026-11-10T10:00:00Z',
        ),
      };

      // 100 USD * 5.0 = 500 BRL (em centavos: 10000 -> 50000)
      expect(
        convertCents(10000, fromCurrency: 'USD', toCurrency: 'BRL', rates: rates),
        50000,
      );

      // 500 BRL -> USD = 100 USD
      expect(
        convertCents(50000, fromCurrency: 'BRL', toCurrency: 'USD', rates: rates),
        10000,
      );

      // 100 EUR -> USD = 100 * (6.0 / 5.0) = 120 USD
      expect(
        convertCents(10000, fromCurrency: 'EUR', toCurrency: 'USD', rates: rates),
        12000,
      );

      // 700 CAD -> AUD = 700 * (4.0 / 3.5) = 800 AUD
      expect(
        convertCents(70000, fromCurrency: 'CAD', toCurrency: 'AUD', rates: rates),
        80000,
      );
    });
  });

  group('Multi-Moeda: Compatibilidade JSON Schema v: 7', () {
    test('decodifica JSON legado sem campos de moeda com defaults BRL', () {
      final json = {
        'v': 7,
        'accounts': [
          {'id': 'a1', 'name': 'Conta Brasil', 'type': 'Corrente', 'opening': 10000},
        ],
        'cats': <Map<String, dynamic>>[],
        'txs': [
          {
            'id': 't1',
            'acc': 'a1',
            'date': '2026-11-10',
            'payee': 'Mercado',
            'cat': 'Alimentação',
            'memo': '',
            'amt': -5000,
            'rec': true,
          },
        ],
      };

      final db = Database.fromJson(json);
      expect(db.v, 7);
      expect(db.effectiveBaseCurrency, 'BRL');
      expect(db.accounts.first.effectiveCurrency, 'BRL');
      expect(db.txs.first.rate, isNull);

      // Ao serializar conta BRL, omite 'currency' e 'baseCurrency' padrão?
      final encoded = db.toJson();
      expect(encoded['v'], 7);
      expect((encoded['accounts'] as List).first.containsKey('currency'), isFalse);
    });

    test('preserva baseCurrency, rates, Account.currency e Transaction.rate no round-trip', () {
      final db = Database(
        baseCurrency: 'USD',
        rates: {
          'USD': const CurrencyRateInfo(
            rate: 5.5,
            manual: true,
            updatedAt: '2026-11-10T12:00:00Z',
            source: 'Manual',
          ),
        },
        accounts: [
          Account(id: 'a1', name: 'Conta USD', type: 'Corrente', opening: 100000, currency: 'USD'),
        ],
        txs: [
          Transaction(
            id: 't1',
            acc: 'a1',
            date: '2026-11-10',
            payee: 'Salary',
            cat: 'Salário',
            amt: 200000,
            rate: 5.45,
          ),
        ],
      );

      final roundTrip = Database.fromJson(db.toJson());
      expect(roundTrip.effectiveBaseCurrency, 'USD');
      expect(roundTrip.rates['USD']?.rate, 5.5);
      expect(roundTrip.rates['USD']?.manual, isTrue);
      expect(roundTrip.accounts.first.effectiveCurrency, 'USD');
      expect(roundTrip.txs.first.rate, 5.45);
    });
  });

  group('Multi-Moeda: Regra Diária de Cotações (CurrencyRateService)', () {
    test('não consulta online se todas as contas ativas estiverem na moeda base', () {
      final db = Database(
        baseCurrency: 'BRL',
        accounts: [
          Account(id: 'a1', name: 'Conta BR', type: 'Corrente', opening: 0),
        ],
      );
      expect(CurrencyRateService.shouldRefreshOnline(db), isFalse);
    });

    test('consulta online quando existe conta estrangeira sem cotação ou desatualizada e pula se já atualizada hoje', () {
      final dbMissing = Database(
        baseCurrency: 'BRL',
        accounts: [
          Account(id: 'a1', name: 'Conta BR', type: 'Corrente', opening: 0),
          Account(id: 'a2', name: 'Nomad', type: 'Corrente', opening: 0, currency: 'USD'),
        ],
      );
      expect(CurrencyRateService.shouldRefreshOnline(dbMissing), isTrue);

      final todayIso = DateTime.now().toIso8601String();
      final dbFresh = Database(
        baseCurrency: 'BRL',
        rates: {
          'USD': CurrencyRateInfo(rate: 5.7, updatedAt: todayIso),
        },
        accounts: dbMissing.accounts,
      );
      expect(CurrencyRateService.shouldRefreshOnline(dbFresh), isFalse);

      final staleDate = DateTime.now().subtract(const Duration(days: 2)).toIso8601String();
      final dbStale = Database(
        baseCurrency: 'BRL',
        rates: {
          'USD': CurrencyRateInfo(rate: 5.7, updatedAt: staleDate),
        },
        accounts: dbMissing.accounts,
      );
      expect(CurrencyRateService.shouldRefreshOnline(dbStale), isTrue);
    });
  });

  group('Multi-Moeda: MoneyStore, Transferência, Relatórios e Fluxo de Caixa', () {
    test('consolida saldo em moeda base configurável e preserva transferência com câmbio manual (IOF/spread)', () {
      final store = MoneyStore(autoBoot: false);
      store.db.accounts.clear();
      store.db.txs.clear();
      store.db.rates['USD'] = const CurrencyRateInfo(
        rate: 5.0,
        updatedAt: '2026-11-10T10:00:00Z',
      );

      final brlErr = store.saveAccount(
        name: 'Itaú',
        type: 'Corrente',
        openingCents: 100000, // R$ 1.000,00
        closeDay: 1,
        dueDay: 1,
        payAccId: '',
        currency: 'BRL',
      );
      expect(brlErr, isNull);
      final brlId = store.selectedAccountId;

      final usdErr = store.saveAccount(
        name: 'Wise USD',
        type: 'Corrente',
        openingCents: 0,
        closeDay: 1,
        dueDay: 1,
        payAccId: '',
        currency: 'USD',
      );
      expect(usdErr, isNull);
      final usdId = store.selectedAccountId;

      // Transferência BRL -> USD com valor ajustado manualmente (R$ 520,00 -> US$ 100,00)
      store.addTransaction(
        accId: brlId,
        date: todayISO(),
        payee: 'Remessa Internacional',
        catSelection: 'xfer:$usdId',
        memo: 'Com spread e IOF',
        signedAmt: -52000,
        peerSignedAmt: 10000,
        txRate: 5.20,
      );

      expect(store.balance(store.accById(brlId)!), 48000); // R$ 480,00
      expect(store.balance(store.accById(usdId)!), 10000); // US$ 100,00

      // Consolidado em BRL: 480,00 + (100,00 * 5.0) = R$ 980,00 (98000 centavos)
      expect(store.totalBalance(predicted: false), 98000);

      // Troca moeda base para USD: 480 BRL / 5.0 (= 96 USD) + 100 USD = 196 USD
      store.setBaseCurrency('USD');
      expect(store.baseCurrency, 'USD');
      expect(store.totalBalance(predicted: false), 19600);
    });

    test('Relatório Mensal e Fluxo de Caixa convertem múltiplas moedas para base e respeitam filtro de moeda única', () {
      final store = MoneyStore(autoBoot: false);
      store.db.accounts.clear();
      store.db.txs.clear();
      store.db.baseCurrency = 'BRL';
      store.db.rates['EUR'] = const CurrencyRateInfo(
        rate: 6.0,
        updatedAt: '2026-11-10T10:00:00Z',
      );

      store.db.accounts.addAll([
        Account(id: 'a_brl', name: 'Conta BR', type: 'Corrente', opening: 100000, currency: null),
        Account(id: 'a_eur', name: 'Conta EUR', type: 'Corrente', opening: 10000, currency: 'EUR'), // € 100 = R$ 600
      ]);

      store.db.txs.addAll([
        Transaction(
          id: 't1',
          acc: 'a_brl',
          date: '2026-11-05',
          payee: 'Mercado',
          cat: 'Alimentação',
          amt: -20000, // -R$ 200
          rec: true,
        ),
        Transaction(
          id: 't2',
          acc: 'a_eur',
          date: '2026-11-06',
          payee: 'Hotel Paris',
          cat: 'Viagem',
          amt: -10000, // -€ 100 (= -R$ 600)
          rec: true,
          rate: 6.0,
        ),
      ]);
      store.markIndexesDirty();

      // Relatório consolidado (todas as contas) -> BRL: despesa total = 200 + 600 = 800 (80000 centavos)
      final repAll = store.buildMonthlyReport('2026-11');
      expect(repAll.currency, 'BRL');
      expect(repAll.totalExpense, 80000);

      // Relatório filtrado apenas para conta EUR -> EUR nativo: despesa = 100 EUR (10000 centavos)
      final repEur = store.buildMonthlyReport('2026-11', accountFilterIds: {'a_eur'});
      expect(repEur.currency, 'EUR');
      expect(repEur.totalExpense, 10000);

      // Fluxo de caixa anual (todas contas) -> BRL: saldo inicial = 1000 + 600 = 1600 BRL, despesas = 800 BRL
      final cfAll = CashFlowEngine.buildMatrix(
        transactions: store.db.txs,
        accounts: store.db.accounts,
        periodKind: CashFlowPeriodKind.monthly,
        year: 2026,
        baseCurrency: store.baseCurrency,
        rates: store.db.rates,
      );
      expect(cfAll.currency, 'BRL');
      expect(cfAll.priorBalancePeriodTotals.first, 160000);
      expect(cfAll.expenseSection.grandTotal, 80000);

      // Fluxo de caixa filtrado para conta EUR -> EUR nativo: saldo inicial = 100 EUR, despesas = 100 EUR
      final cfEur = CashFlowEngine.buildMatrix(
        transactions: store.db.txs,
        accounts: store.db.accounts,
        periodKind: CashFlowPeriodKind.monthly,
        year: 2026,
        accountFilterIds: {'a_eur'},
        baseCurrency: store.baseCurrency,
        rates: store.db.rates,
      );
      expect(cfEur.currency, 'EUR');
      expect(cfEur.priorBalancePeriodTotals.first, 10000);
      expect(cfEur.expenseSection.grandTotal, 10000);
    });

    test('CSV Export e Import preservam moeda, valor oficial, valor na moeda padrão e transferências cross-currency', () {
      final store = MoneyStore(autoBoot: false);
      store.db.accounts.clear();
      store.db.txs.clear();
      store.db.baseCurrency = 'BRL';
      store.db.rates['USD'] = const CurrencyRateInfo(
        rate: 5.0,
        updatedAt: '2026-11-10T10:00:00Z',
      );

      store.saveAccount(
        name: 'Itaú',
        type: 'Corrente',
        openingCents: 0,
        closeDay: 1,
        dueDay: 1,
        payAccId: '',
        currency: 'BRL',
      );
      final brlId = store.selectedAccountId;

      store.saveAccount(
        name: 'Wise USD',
        type: 'Corrente',
        openingCents: 0,
        closeDay: 1,
        dueDay: 1,
        payAccId: '',
        currency: 'USD',
      );
      final usdId = store.selectedAccountId;

      // Transferência com taxa customizada (spread/IOF: R$ 520,00 -> US$ 100,00; rate = 5.20)
      store.addTransaction(
        accId: brlId,
        date: '2026-11-10',
        payee: 'Remessa Câmbio',
        catSelection: 'xfer:$usdId',
        memo: 'Com IOF',
        signedAmt: -52000,
        peerSignedAmt: 10000,
        txRate: 5.20,
      );
      // Gasto normal em USD com taxa histórica 5.10
      store.addTransaction(
        accId: usdId,
        date: '2026-11-11',
        payee: 'Cloud Hosting',
        catSelection: 'Serviços',
        memo: 'Servidor',
        signedAmt: -2000,
        txRate: 5.10,
      );

      final csv = store.exportCSVString();
      expect(csv.contains('"Moeda";"Moeda Padrão";"Valor Moeda Padrão";"Taxa Câmbio";"Valor Contrapartida";"Moeda Contrapartida";"Taxa Transferência"'), isTrue);
      // Origem BRL: -520,00 BRL -> contrapartida 100,00 USD
      expect(csv.contains('"-520,00";"Sim";"";"Não";"Sim";"BRL";"BRL";"-520,00";"";"100,00";"USD";"0,192308"'), isTrue);
      // Destino USD: 100,00 USD = 520,00 BRL (taxa 5,2000), contrapartida -520,00 BRL
      expect(csv.contains('"100,00";"Sim";"";"Não";"Sim";"USD";"BRL";"520,00";"5,2000";"-520,00";"BRL";"5,200000"'), isTrue);
      // Despesa USD: -20,00 USD = -102,00 BRL (taxa histórica 5,1000)
      expect(csv.contains('"-20,00";"Não";"";"Não";"Sim";"USD";"BRL";"-102,00";"5,1000";"";"";""'), isTrue);

      // Reimportação em base limpa deve recriar Itaú (BRL), Wise USD (USD), taxa histórica e vínculo xfer
      final imported = CSVImporter.parse(
        content: csv,
        existingAccounts: [],
        existingCats: [],
        existingTxs: [],
        baseCurrency: 'BRL',
        rates: store.db.rates,
      );
      expect(imported.newAccounts.length, 2);
      final impBrlAcc = imported.newAccounts.firstWhere((a) => a.name == 'Itaú');
      final impUsdAcc = imported.newAccounts.firstWhere((a) => a.name == 'Wise USD');
      expect(impBrlAcc.effectiveCurrency, 'BRL');
      expect(impUsdAcc.effectiveCurrency, 'USD');

      expect(imported.newTxs.length, 3);
      final legBrl = imported.newTxs.firstWhere((t) => t.acc == impBrlAcc.id);
      final legUsd = imported.newTxs.firstWhere((t) => t.acc == impUsdAcc.id && t.amt == 10000);
      final expUsd = imported.newTxs.firstWhere((t) => t.acc == impUsdAcc.id && t.amt == -2000);

      expect(legBrl.amt, -52000);
      expect(legUsd.amt, 10000);
      expect(legUsd.rate, closeTo(5.20, 0.0001));
      expect(legBrl.xfer, isNotNull);
      expect(legBrl.xfer, legUsd.xfer);
      expect(legBrl.peer, impUsdAcc.id);
      expect(legUsd.peer, impBrlAcc.id);
      expect(expUsd.rate, closeTo(5.10, 0.0001));
    });
  });
}

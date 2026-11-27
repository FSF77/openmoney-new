import 'package:flutter_test/flutter_test.dart';
import 'package:openmoney/models/openmoney_models.dart';
import 'package:openmoney/services/analytics_engine.dart';
import 'package:openmoney/services/cash_flow_engine.dart';
import 'package:openmoney/services/financial_insights_engine.dart';
import 'package:openmoney/services/investment_engine.dart';
import 'package:openmoney/services/investment_insights_engine.dart';
import 'package:openmoney/services/investment_quote_service.dart';
import 'package:openmoney/store/money_store.dart';

void main() {
  group('InvestmentEngine - Preço Médio de Compra e Venda', () {
    test('Compra múltipla com taxas calcula PM ponderado em centavos', () {
      final asset = InvestAsset(
        id: 'petr',
        ticker: 'PETR4',
        name: 'Petrobras PN',
        assetClass: InvestAssetClass.stock,
        accountId: 'inv1',
        currentPriceCents: 3800,
      );

      final ops = [
        InvestOperation(
          assetId: 'petr',
          accountId: 'inv1',
          type: InvestOpType.buy,
          date: '2026-01-10',
          quantity: 100,
          unitPriceCents: 3000,
          feesCents: 1000, // R$ 10,00 de taxa -> total 301000
        ),
        InvestOperation(
          assetId: 'petr',
          accountId: 'inv1',
          type: InvestOpType.buy,
          date: '2026-02-10',
          quantity: 100,
          unitPriceCents: 3400,
          feesCents: 1000, // total 341000
        ),
      ];

      final pos = InvestmentEngine.computeAssetPosition(asset, ops);
      expect(pos.currentQty, 200);
      expect(pos.currentCostBasisCents, 642000);
      expect(pos.avgBuyPriceCents, 3210); // R$ 32,10
      expect(pos.currentNetValueCents, 760000); // 200 * 38,00
      expect(pos.unrealizedPnlCents, 118000);
    });

    test('Venda parcial preserva PM de compra e calcula PM de venda e lucro realizado', () {
      final asset = InvestAsset(
        id: 'hglg',
        ticker: 'HGLG11',
        name: 'CSHG Logística',
        assetClass: InvestAssetClass.fii,
        accountId: 'inv1',
        currentPriceCents: 16000,
      );

      final ops = [
        InvestOperation(
          assetId: 'hglg',
          accountId: 'inv1',
          type: InvestOpType.buy,
          date: '2026-01-05',
          quantity: 100,
          unitPriceCents: 15000, // R$ 150,00 -> 1500000
        ),
        InvestOperation(
          assetId: 'hglg',
          accountId: 'inv1',
          type: InvestOpType.sell,
          date: '2026-03-05',
          quantity: 40,
          unitPriceCents: 17000,
          feesCents: 0, // R$ 6.800,00 líquido
        ),
        InvestOperation(
          assetId: 'hglg',
          accountId: 'inv1',
          type: InvestOpType.fiiYield,
          date: '2026-03-15',
          quantity: 1,
          unitPriceCents: 6600,
          totalCents: 6600,
        ),
      ];

      final pos = InvestmentEngine.computeAssetPosition(asset, ops);
      expect(pos.currentQty, 60);
      expect(pos.avgBuyPriceCents, 15000); // PM compra NÃO altera na venda!
      expect(pos.avgSellPriceCents, 17000); // PM venda
      expect(pos.realizedPnlCents, 80000); // 40 * (170 - 150) = R$ 800,00
      expect(pos.currentCostBasisCents, 900000);
      expect(pos.totalDividendsCents, 6600);
    });

    test('Amortização reduz PM e Split/Inplit ajustam quantidade preservando custo', () {
      final asset = InvestAsset(
        id: 'xpml',
        ticker: 'XPML11',
        name: 'XP Malls',
        assetClass: InvestAssetClass.fii,
        accountId: 'inv1',
      );
      final ops = [
        InvestOperation(
          assetId: 'xpml',
          accountId: 'inv1',
          type: InvestOpType.buy,
          date: '2026-01-01',
          quantity: 10,
          unitPriceCents: 10000, // 100.000
        ),
        InvestOperation(
          assetId: 'xpml',
          accountId: 'inv1',
          type: InvestOpType.amortization,
          date: '2026-02-01',
          quantity: 1,
          unitPriceCents: 10000,
          totalCents: 10000, // reduz custo para 90.000 -> PM 9.000
        ),
        InvestOperation(
          assetId: 'xpml',
          accountId: 'inv1',
          type: InvestOpType.split,
          date: '2026-03-01',
          quantity: 10, // 1:10 -> 100 cotas, PM 900
          unitPriceCents: 0,
          totalCents: 0,
        ),
      ];
      final pos = InvestmentEngine.computeAssetPosition(asset, ops);
      expect(pos.currentQty, 100);
      expect(pos.currentCostBasisCents, 90000);
      expect(pos.avgBuyPriceCents, 900);
    });

    test('Criptomoeda suporta 8 casas decimais na quantidade mantendo centavos inteiros', () {
      final btc = InvestAsset(
        id: 'btc',
        ticker: 'BTC',
        name: 'Bitcoin',
        assetClass: InvestAssetClass.crypto,
        accountId: 'inv1',
        currentPriceCents: 50000000, // R$ 500.000,00
      );
      final ops = [
        InvestOperation(
          assetId: 'btc',
          accountId: 'inv1',
          type: InvestOpType.buy,
          date: '2026-01-10',
          quantity: 0.00452100,
          unitPriceCents: 40000000, // R$ 400.000,00 -> ~180840 centavos
        ),
      ];
      final pos = InvestmentEngine.computeAssetPosition(btc, ops);
      expect(formatInvestQty(pos.currentQty, InvestAssetClass.crypto), '0,004521');
      expect(pos.currentGrossValueCents, (0.004521 * 50000000).round());
      expect(pos.unrealizedPnlCents, greaterThan(0));
    });

    test('Renda Fixa aplica IR regressivo no CDB e isenção na LCI', () {
      final indicators = MarketIndicators(cdiAnnual: 12.0);
      final cdb = InvestAsset(
        id: 'cdb1',
        ticker: 'CDB 110% CDI',
        name: 'CDB Banco X',
        assetClass: InvestAssetClass.fixedIncome,
        subType: 'CDB',
        accountId: 'inv1',
        indexer: InvestFixedIncomeIndexer.cdi,
        ratePct: 110.0,
        taxExempt: false,
      );
      final lci = InvestAsset(
        id: 'lci1',
        ticker: 'LCI 95% CDI',
        name: 'LCI Banco Y',
        assetClass: InvestAssetClass.fixedIncome,
        subType: 'LCI',
        accountId: 'inv1',
        indexer: InvestFixedIncomeIndexer.cdi,
        ratePct: 95.0,
        taxExempt: true,
      );

      final cdbOps = [
        InvestOperation(
          assetId: 'cdb1',
          accountId: 'inv1',
          type: InvestOpType.buy,
          date: '2026-01-01',
          quantity: 1,
          unitPriceCents: 1000000, // R$ 10.000,00
        ),
      ];
      final lciOps = [
        InvestOperation(
          assetId: 'lci1',
          accountId: 'inv1',
          type: InvestOpType.buy,
          date: '2026-01-01',
          quantity: 1,
          unitPriceCents: 1000000,
        ),
      ];

      final cdbPos = InvestmentEngine.computeAssetPosition(
        cdb,
        cdbOps,
        indicators: indicators,
        asOfDateIso: '2026-06-01', // ~151 dias -> IR 22.5%
      );
      final lciPos = InvestmentEngine.computeAssetPosition(
        lci,
        lciOps,
        indicators: indicators,
        asOfDateIso: '2026-06-01',
      );

      expect(cdbPos.irRatePct, 22.5);
      expect(cdbPos.estimatedTaxCents, greaterThan(0));
      expect(lciPos.irRatePct, 0.0);
      expect(lciPos.estimatedTaxCents, 0);
    });
  });

  group('MoneyStore - Integração Caixa Transferência (-) / (+) e Saldo Atualizado', () {
    test('Compra e venda geram Transferência (-) / (+) excluídas dos relatórios', () {
      final store = MoneyStore();
      final invAcc = Account(
        id: 'inv_acc',
        name: 'XP Investimentos',
        type: 'Investimento',
        opening: 1000000, // R$ 10.000,00 em caixa
      );
      store.db = Database(accounts: [invAcc]);

      final asset = InvestAsset(
        id: 'vale3',
        ticker: 'VALE3',
        name: 'Vale ON',
        assetClass: InvestAssetClass.stock,
        accountId: 'inv_acc',
        currentPriceCents: 7000, // R$ 70,00
      );
      store.addOrUpdateInvestAsset(asset);

      store.addInvestOperation(
        InvestOperation(
          assetId: 'vale3',
          accountId: 'inv_acc',
          type: InvestOpType.buy,
          date: todayISO(),
          quantity: 100,
          unitPriceCents: 6000, // R$ 6.000,00
        ),
        affectAccountCash: true,
      );

      // Caixa livre caiu para R$ 4.000,00
      expect(store.balance(invAcc), 400000);
      // Saldo atualizado da conta = R$ 4.000 (caixa) + R$ 7.000 (100 * 70) = R$ 11.000
      expect(store.accountTotalBalance(invAcc), 1100000);

      // Transação gerada é reconhecida como transferência e excluída de gastos
      final linkedTx = store.db.txs.first;
      expect(linkedTx.cat, 'Transferência (-)');
      expect(isTransferTransaction(linkedTx), isTrue);

      // Provento usa categoria configurável padrão 'Investimentos (+) › Dividendos'
      store.addInvestOperation(
        InvestOperation(
          assetId: 'vale3',
          accountId: 'inv_acc',
          type: InvestOpType.dividend,
          date: todayISO(),
          quantity: 1,
          unitPriceCents: 25000,
          totalCents: 25000,
        ),
        affectAccountCash: true,
      );
      expect(store.db.txs.last.cat, 'Investimentos (+) › Dividendos');
      expect(store.balance(invAcc), 425000);
    });

    test('updateInvestOperation atualiza operação e transação vinculada no caixa', () {
      final store = MoneyStore();
      final invAcc = Account(
        id: 'inv_acc',
        name: 'Corretora Cripto',
        type: 'Investimento',
        opening: 100000, // R$ 1.000,00
      );
      store.db = Database(accounts: [invAcc]);

      final usdc = InvestAsset(
        id: 'usdc',
        ticker: 'USDC',
        name: 'USD Coin',
        assetClass: InvestAssetClass.crypto,
        accountId: 'inv_acc',
        currentPriceCents: 560,
      );
      store.addOrUpdateInvestAsset(usdc);

      final op = InvestOperation(
        id: 'op_usdc_1',
        assetId: 'usdc',
        accountId: 'inv_acc',
        type: InvestOpType.buy,
        date: todayISO(),
        quantity: 10.036,
        unitPriceCents: 556,
        totalCents: 5584, // R$ 55,84 exato
      );
      store.addInvestOperation(op, affectAccountCash: true);

      expect(store.balance(invAcc), 100000 - 5584);
      expect(store.db.txs.length, 1);
      expect(store.db.txs.first.amt, -5584);

      // Edita para R$ 60,00
      store.updateInvestOperation(
        op.copyWith(quantity: 10.7, totalCents: 6000),
        affectAccountCash: true,
      );
      expect(store.balance(invAcc), 100000 - 6000);
      expect(store.db.txs.first.amt, -6000);

      // Edita desmarcando movimentação de caixa -> remove transação vinculada
      store.updateInvestOperation(
        op.copyWith(quantity: 10.7, totalCents: 6000),
        affectAccountCash: false,
      );
      expect(store.db.txs, isEmpty);
      expect(store.balance(invAcc), 100000);
    });

    test('Editar conta do ativo migra operações e transações vinculadas no caixa', () {
      final store = MoneyStore();
      final acc1 = Account(
        id: 'inv1',
        name: 'Corretora A',
        type: 'Investimento',
        opening: 50000,
      );
      final acc2 = Account(
        id: 'inv2',
        name: 'Corretora B',
        type: 'Investimento',
        opening: 50000,
      );
      store.db = Database(accounts: [acc1, acc2]);

      final asset = InvestAsset(
        id: 'ast_mig',
        ticker: 'BBAS3',
        name: 'Banco do Brasil',
        assetClass: InvestAssetClass.stock,
        accountId: 'inv1',
        currentPriceCents: 2800,
      );
      store.addOrUpdateInvestAsset(asset);

      store.addInvestOperation(
        InvestOperation(
          id: 'op_mig',
          assetId: 'ast_mig',
          accountId: 'inv1',
          type: InvestOpType.buy,
          date: todayISO(),
          quantity: 10,
          unitPriceCents: 2500,
          totalCents: 25000,
        ),
        affectAccountCash: true,
      );

      expect(store.balance(acc1), 25000);
      expect(store.balance(acc2), 50000);

      // Edita o ativo mudando de Corretora A -> Corretora B
      store.addOrUpdateInvestAsset(asset.copyWith(accountId: 'inv2'));

      expect(store.db.investOps.first.accountId, 'inv2');
      expect(store.db.txs.first.acc, 'inv2');
      expect(store.balance(acc1), 50000); // restaurado
      expect(store.balance(acc2), 25000); // debitado na nova conta
      expect(store.accountTotalBalance(acc2), 53000); // 25000 caixa + 28000 ativos
    });

    test('Mesmo ativo comprado em duas corretoras consolida global e separa por corretora', () {
      final store = MoneyStore();
      final xp = Account(id: 'xp', name: 'XP', type: 'Investimento', opening: 0);
      final rico = Account(id: 'rico', name: 'Rico', type: 'Investimento', opening: 0);
      store.db = Database(accounts: [xp, rico]);

      final petr = InvestAsset(
        id: 'petr4',
        ticker: 'PETR4',
        name: 'Petrobras',
        assetClass: InvestAssetClass.stock,
        accountId: 'xp',
        currentPriceCents: 4000,
      );
      store.addOrUpdateInvestAsset(petr);

      store.addInvestOperation(
        InvestOperation(
          assetId: 'petr4',
          accountId: 'xp',
          type: InvestOpType.initialPosition,
          date: '2026-01-10',
          quantity: 100,
          unitPriceCents: 3000,
        ),
        affectAccountCash: false,
      );
      store.addInvestOperation(
        InvestOperation(
          assetId: 'petr4',
          accountId: 'rico',
          type: InvestOpType.initialPosition,
          date: '2026-02-10',
          quantity: 50,
          unitPriceCents: 3600,
        ),
        affectAccountCash: false,
      );

      final xpSummary = store.portfolioSummary(accountId: 'xp');
      final ricoSummary = store.portfolioSummary(accountId: 'rico');
      final globalSummary = store.portfolioSummary();

      expect(xpSummary.positions.single.currentQty, 100);
      expect(xpSummary.totalMarketValueNetCents, 400000);
      expect(ricoSummary.positions.single.currentQty, 50);
      expect(ricoSummary.totalMarketValueNetCents, 200000);
      expect(globalSummary.positions.single.currentQty, 150);
      expect(globalSummary.positions.single.avgBuyPriceCents, 3200);
      expect(store.accountTotalBalance(rico), 200000);
    });

    test('InvestmentQuoteService parseBinancePriceJson, CoinGecko e normalização cripto', () {
      expect(
        InvestmentQuoteService.parseBinancePriceJson(
            '{"symbol":"USDCBRL","price":"5.78500000"}'),
        closeTo(5.785, 1e-6),
      );
      expect(
        InvestmentQuoteService.parseCoinbasePriceJson(
            '{"data":{"base":"BTC","currency":"BRL","amount":"542100.50"}}'),
        closeTo(542100.50, 1e-6),
      );
      expect(
        InvestmentQuoteService.parseMercadoBitcoinPriceJson(
            '{"ticker":{"last":"541990.00"}}'),
        closeTo(541990.00, 1e-6),
      );
      final bcbSeries = InvestmentQuoteService.parseBcbDailySeriesJson(
        '[{"data":"08/10/2026","valor":"0.055131"},{"data":"09/10/2026","valor":"0.055131"}]',
      );
      expect(bcbSeries['2026-10-08'], closeTo(0.055131, 1e-8));
      expect(bcbSeries['2026-10-09'], closeTo(0.055131, 1e-8));
      final cg = InvestmentQuoteService.parseCoinGeckoPricesJson(
        '{"bitcoin":{"brl":540123.45,"usd":93500},"usd-coin":{"brl":5.79,"usd":1.0}}',
      );
      expect(cg['bitcoin']?['brl'], 540123.45);
      expect(cg['usd-coin']?['brl'], 5.79);

      expect(InvestmentQuoteService.normalizedCryptoBase('BITCOIN'), 'BTC');
      expect(InvestmentQuoteService.normalizedCryptoBase('usdc-brl'), 'USDC');
      expect(
        InvestmentQuoteService.yahooSymbolFor(InvestAsset(
          ticker: 'BITCOIN',
          name: 'Bitcoin',
          assetClass: InvestAssetClass.crypto,
          accountId: 'inv1',
        )),
        'BTC-BRL',
      );
    });

    test('estimateSellIr calcula IR regressivo FIFO nas 4 faixas e gera lançamento de IR no resgate', () {
      final cdb = InvestAsset(
        id: 'cdb_ir',
        ticker: 'CDB 110% CDI',
        name: 'CDB Banco X',
        assetClass: InvestAssetClass.fixedIncome,
        subType: 'CDB',
        accountId: 'inv1',
        taxExempt: false,
      );
      final buyOp = InvestOperation(
        id: 'buy_cdb',
        assetId: 'cdb_ir',
        accountId: 'inv1',
        type: InvestOpType.buy,
        date: '2025-01-01',
        quantity: 1,
        unitPriceCents: 1000000, // R$ 10.000,00
        totalCents: 1000000,
      );

      // <= 180 dias -> 22.5% sobre R$ 1.000,00 de lucro = R$ 225,00
      final e180 = InvestmentEngine.estimateSellIr(
        asset: cdb,
        priorOps: [buyOp],
        sellDateIso: '2025-05-01', // 120 dias
        sellQty: 1,
        grossSellCents: 1100000,
      );
      expect(e180.irCents, 22500);
      expect(e180.effectiveRatePct, closeTo(22.5, 0.1));

      // 181-360 dias -> 20.0% = R$ 200,00
      final e360 = InvestmentEngine.estimateSellIr(
        asset: cdb,
        priorOps: [buyOp],
        sellDateIso: '2025-09-01', // 243 dias
        sellQty: 1,
        grossSellCents: 1100000,
      );
      expect(e360.irCents, 20000);

      // 361-720 dias -> 17.5% = R$ 175,00
      final e720 = InvestmentEngine.estimateSellIr(
        asset: cdb,
        priorOps: [buyOp],
        sellDateIso: '2026-03-01', // 424 dias
        sellQty: 1,
        grossSellCents: 1100000,
      );
      expect(e720.irCents, 17500);

      // > 720 dias -> 15.0% = R$ 150,00
      final eOver = InvestmentEngine.estimateSellIr(
        asset: cdb,
        priorOps: [buyOp],
        sellDateIso: '2027-02-01', // 761 dias
        sellQty: 1,
        grossSellCents: 1100000,
      );
      expect(eOver.irCents, 15000);

      // MoneyStore: venda cria Transferência (+) bruto e Investimentos (-) › IR negativo
      final store = MoneyStore();
      final invAcc = Account(
        id: 'inv1',
        name: 'Corretora',
        type: 'Investimento',
        opening: 1000000,
      );
      store.db = Database(accounts: [invAcc]);
      store.addOrUpdateInvestAsset(cdb);
      store.addInvestOperation(buyOp, affectAccountCash: true);
      expect(store.balance(invAcc), 0);

      final sellOp = InvestOperation(
        id: 'sell_cdb',
        assetId: 'cdb_ir',
        accountId: 'inv1',
        type: InvestOpType.sell,
        date: '2026-03-01',
        quantity: 1,
        unitPriceCents: 1100000,
        taxCents: 17500,
        totalCents: 1100000,
      );
      store.addInvestOperation(sellOp, affectAccountCash: true);

      // Saldo líquido recebido = R$ 11.000 - R$ 175 IR = R$ 10.825,00
      expect(store.balance(invAcc), 1082500);
      final irTx = store.db.txs.where((t) => t.cat == 'Investimentos (-) › IR').toList();
      expect(irTx.length, 1);
      expect(irTx.first.amt, -17500);

      // Excluir a venda remove tanto Transferência (+) quanto o lançamento de IR
      store.deleteInvestOperation('sell_cdb');
      expect(store.db.txs.where((t) => t.cat == 'Investimentos (-) › IR'), isEmpty);
      expect(store.balance(invAcc), 0);

      // ensureCategoryPath cria pai e filha automaticamente se não existir
      expect(store.allCategoryPaths('Despesa').contains('Investimentos (-) › IR'), isTrue);

      // InvestAsset.inactive preserva no round-trip JSON
      final inactiveCdb = cdb.copyWith(inactive: true);
      final roundTrip = InvestAsset.fromJson(inactiveCdb.toJson());
      expect(roundTrip.inactive, isTrue);
    });

    test('AnalyticsEngine inclui valor atualizado da carteira no Patrimônio Líquido', () {
      final store = MoneyStore();
      final invAcc = Account(
        id: 'inv1',
        name: 'Corretora',
        type: 'Investimento',
        opening: 1000000, // R$ 10.000,00
      );
      store.db = Database(accounts: [invAcc]);

      final petr = InvestAsset(
        id: 'petr4',
        ticker: 'PETR4',
        name: 'Petrobras',
        assetClass: InvestAssetClass.stock,
        accountId: 'inv1',
        currentPriceCents: 4200, // R$ 42,00
      );
      store.addOrUpdateInvestAsset(petr);
      store.addInvestOperation(
        InvestOperation(
          id: 'buy_petr',
          assetId: 'petr4',
          accountId: 'inv1',
          type: InvestOpType.buy,
          date: todayISO(),
          quantity: 100,
          unitPriceCents: 4000, // R$ 4.000,00 aplicados -> R$ 6.000 caixa
          totalCents: 400000,
        ),
        affectAccountCash: true,
      );

      final curYM = todayISO().substring(0, 7);
      final snap = AnalyticsEngine.compute(
        store,
        AnalyticsFilter(fromYM: curYM, toYM: curYM, isAllTime: true),
      );
      // Caixa R$ 6.000 + Carteira R$ 4.200 = R$ 10.200,00
      expect(snap.cashNetWorth, 600000);
      expect(snap.investmentsNetWorth, 420000);
      expect(snap.netWorth, 1020000);
    });

    test('Calendário ANBIMA exclui fins de semana, feriados móveis e 20/11 >= 2024', () {
      // Páscoa de 2026 é 05/04/2026: Carnaval 16-17/02, Sexta Santa 03/04, Corpus Christi 04/06
      expect(InvestmentEngine.easterSunday(2026), DateTime(2026, 4, 5));
      expect(InvestmentEngine.isAnbimaBusinessDay(DateTime(2026, 2, 16)), isFalse);
      expect(InvestmentEngine.isAnbimaBusinessDay(DateTime(2026, 2, 17)), isFalse);
      expect(InvestmentEngine.isAnbimaBusinessDay(DateTime(2026, 4, 3)), isFalse);
      expect(InvestmentEngine.isAnbimaBusinessDay(DateTime(2026, 6, 4)), isFalse);
      expect(InvestmentEngine.isAnbimaBusinessDay(DateTime(2026, 11, 20)), isFalse);
      // 20/11/2023 (segunda) ainda não era feriado nacional
      expect(InvestmentEngine.isAnbimaBusinessDay(DateTime(2023, 11, 20)), isTrue);
      // 29/12/2025 -> 26/11/2026 possui exatamente 227 dias úteis ANBIMA
      expect(
        InvestmentEngine.businessDaysAnbima(
          DateTime(2025, 12, 29),
          DateTime(2026, 11, 26),
        ),
        227,
      );
    });

    test('CDB Prefixado 14,38% a.a. usa dias úteis ANBIMA e exibe bruto como principal', () {
      final cdbPre = InvestAsset(
        id: 'cdb_pre',
        ticker: 'CDB PRE 14,38%',
        name: 'CDB Prefixado',
        assetClass: InvestAssetClass.fixedIncome,
        subType: 'CDB',
        accountId: 'inv1',
        indexer: InvestFixedIncomeIndexer.prefixado,
        ratePct: 14.38,
      );
      final ops = [
        InvestOperation(
          assetId: 'cdb_pre',
          accountId: 'inv1',
          type: InvestOpType.buy,
          date: '2025-12-29',
          quantity: 1,
          unitPriceCents: 500000,
          totalCents: 500000,
        ),
      ];
      final pos = InvestmentEngine.computeAssetPosition(
        cdbPre,
        ops,
        asOfDateIso: '2026-11-26',
      );
      // 332 dias corridos -> alíquota regressiva 20%
      expect(pos.daysHeld, 332);
      expect(pos.irRatePct, 20.0);
      expect(pos.currentGrossValueCents, inInclusiveRange(564200, 564500));
      expect(pos.estimatedTaxCents,
          ((pos.currentGrossValueCents - 500000) * 0.20).round());
      expect(pos.currentNetValueCents,
          pos.currentGrossValueCents - pos.estimatedTaxCents);
      expect(pos.unrealizedPnlCents, pos.currentGrossValueCents - 500000);
    });

    test('CDB Pós-fixado acumula histórico diário do CDI e usa fallback quando falta data', () {
      final indicators = MarketIndicators(
        cdiAnnual: 14.90,
        cdiDailySeries: {
          '2026-10-08': 0.055131,
          '2026-10-09': 0.055131,
          // 10 e 11 são sábado/domingo; 12/10 é feriado; 13/10 com taxa maior
          '2026-10-13': 0.060000,
        },
      );
      final cdbCdi = InvestAsset(
        id: 'cdb_cdi',
        ticker: 'CDB 100% CDI',
        name: 'CDB Pós-fixado',
        assetClass: InvestAssetClass.fixedIncome,
        subType: 'CDB',
        accountId: 'inv1',
        indexer: InvestFixedIncomeIndexer.cdi,
        ratePct: 100.0,
      );
      final ops = [
        InvestOperation(
          assetId: 'cdb_cdi',
          accountId: 'inv1',
          type: InvestOpType.buy,
          date: '2026-10-08',
          quantity: 1,
          unitPriceCents: 500000,
          totalCents: 500000,
        ),
      ];
      // Até 15/10: 08, 09, 13 (da série) + 14 (fallback dia útil)
      final pos = InvestmentEngine.computeAssetPosition(
        cdbCdi,
        ops,
        indicators: indicators,
        asOfDateIso: '2026-10-15',
      );
      expect(pos.currentGrossValueCents, greaterThan(501100));
      expect(pos.currentGrossValueCents, lessThan(501200));
    });

    test('tesouroBondKeyForAsset normaliza títulos com taxa e parseTesouroTransparenteCsv extrai PU Venda', () {
      InvestAsset makeTesouro(String ticker, {String name = '', String? mat}) =>
          InvestAsset(
            ticker: ticker,
            name: name.isEmpty ? ticker : name,
            assetClass: InvestAssetClass.tesouro,
            accountId: 'inv1',
            maturityDate: mat,
          );

      expect(
        InvestmentQuoteService.tesouroBondKeyForAsset(
          makeTesouro('TESOURO IPCA+ 2029 / IPCA + 7,89%'),
        ),
        'ipca:2029',
      );
      expect(
        InvestmentQuoteService.tesouroBondKeyForAsset(
          makeTesouro('TESOURO IPCA+ 2040 / IPCA + 6,91%'),
        ),
        'ipca:2040',
      );
      expect(
        InvestmentQuoteService.tesouroBondKeyForAsset(
          makeTesouro('TESOURO IPCA+ 2040 / IPCA + 7,11%'),
        ),
        'ipca:2040',
      );
      expect(
        InvestmentQuoteService.tesouroBondKeyForAsset(
          makeTesouro('Tesouro Direto Prefixado 2032'),
        ),
        'prefixado:2032',
      );
      expect(
        InvestmentQuoteService.tesouroBondKeyForAsset(
          makeTesouro('Tesouro Direto IPCA+ 2050'),
        ),
        'ipca:2050',
      );
      expect(
        InvestmentQuoteService.tesouroBondKeyForAsset(
          makeTesouro('Tesouro IPCA+ com Juros Semestrais 2035'),
        ),
        'ipca_juros:2035',
      );
      expect(
        InvestmentQuoteService.tesouroBondKeyForAsset(
          makeTesouro('Tesouro Selic 2029'),
        ),
        'selic:2029',
      );
      expect(
        InvestmentQuoteService.tesouroBondKeyForAsset(
          makeTesouro('Tesouro Renda+ 2030'),
        ),
        'renda_mais:2030',
      );

      const csvSample =
          'Tipo Titulo;Data Vencimento;Data Base;Taxa Compra Manha;Taxa Venda Manha;PU Compra Manha;PU Venda Manha;PU Base Manha\n'
          'Tesouro IPCA+;15/05/2029;24/11/2026;7,50;7,62;4000,00;3980,00;3980,00\n'
          'Tesouro IPCA+;15/05/2029;25/11/2026;7,45;7,57;4010,85;3998,28;3998,28\n'
          'Tesouro Prefixado;01/01/2032;25/11/2026;15,27;15,39;486,69;483,85;483,85\n'
          'Tesouro IPCA+;15/08/2050;25/11/2026;7,57;7,69;855,83;833,28;833,28\n'
          'Tesouro Renda+ Aposentadoria Extra;15/12/2049;25/11/2026;7,40;7,52;150,10;145,20;145,20\n'
          'Linha truncada pelo Range';

      final parsed =
          InvestmentQuoteService.parseTesouroTransparenteCsv(csvSample);
      expect(parsed['ipca:2029']?.puVenda, closeTo(3998.28, 1e-6));
      expect(parsed['ipca:2029']?.dataBaseIso, '2026-11-25');
      expect(parsed['prefixado:2032']?.puVenda, closeTo(483.85, 1e-6));
      expect(parsed['ipca:2050']?.puVenda, closeTo(833.28, 1e-6));
      expect(parsed['renda_mais:2049']?.puVenda, closeTo(145.20, 1e-6));
      expect(parsed['renda_mais:2030']?.puVenda, closeTo(145.20, 1e-6));
    });

    test('parseB3FiiDividendsJson, openQtyByAccountOnDate e syncAndScheduleFiiDividends sem duplicar', () async {
      const sampleJson = '''
      {
        "cashDividends": [
          {
            "assetIssued": "BRBTLGCTF000",
            "paymentDate": "25/11/2026",
            "rate": "0,81000000000",
            "relatedTo": "Outubro-2026/2026",
            "approvedOn": "13/11/2026",
            "isinCode": "BRBTLGCTF000",
            "label": "RENDIMENTO",
            "lastDatePrior": "13/11/2026"
          },
          {
            "assetIssued": "BRBTLGR29M15",
            "paymentDate": "25/11/2026",
            "rate": "0,55738698200",
            "relatedTo": "Outubro-2026/2026",
            "approvedOn": "13/11/2026",
            "isinCode": "BRBTLGR29M15",
            "label": "RENDIMENTO",
            "lastDatePrior": "13/11/2026"
          }
        ]
      }
      ''';
      final events =
          InvestmentQuoteService.parseB3FiiDividendsJson('BTLG11', sampleJson);
      expect(events.length, 1); // Ignora recibo BRBTLGR29M15
      expect(events.single.paymentDateIso, '2026-11-25');
      expect(events.single.lastDatePriorIso, '2026-11-13');
      expect(events.single.ratePerQuota, closeTo(0.81, 1e-6));

      final store = MoneyStore(autoBoot: false);
      store.db = Database(
        accounts: [
          Account(id: 'xp', name: 'XP', type: 'Investimento', opening: 0),
        ],
      );
      final btlg = InvestAsset(
        id: 'btlg',
        ticker: 'BTLG11',
        name: 'BTG Pactual Logística',
        assetClass: InvestAssetClass.fii,
        accountId: 'xp',
      );
      store.addOrUpdateInvestAsset(btlg);
      store.addInvestOperation(
        InvestOperation(
          id: 'buy_before',
          assetId: 'btlg',
          accountId: 'xp',
          type: InvestOpType.buy,
          date: '2026-11-10',
          quantity: 100,
          unitPriceCents: 10000,
          totalCents: 1000000,
        ),
        affectAccountCash: false,
      );
      // Compra após Data-Com (13/11) não deve entrar no cálculo do dividendo
      store.addInvestOperation(
        InvestOperation(
          id: 'buy_after',
          assetId: 'btlg',
          accountId: 'xp',
          type: InvestOpType.buy,
          date: '2026-11-18',
          quantity: 50,
          unitPriceCents: 10000,
          totalCents: 500000,
        ),
        affectAccountCash: false,
      );

      final qtyOnCom = InvestmentEngine.openQtyByAccountOnDate(
        assetId: 'btlg',
        ops: store.db.investOps,
        asOfDateIso: '2026-11-13',
      );
      expect(qtyOnCom['xp'], 100);

      final futurePay = DateTime.now().add(const Duration(days: 5));
      final futurePayIso =
          '${futurePay.year}-${futurePay.month.toString().padLeft(2, '0')}-${futurePay.day.toString().padLeft(2, '0')}';

      final res1 = await store.syncAndScheduleFiiDividends(
        preloadedEvents: {
          'btlg': [
            FiiDividendEvent(
              ticker: 'BTLG11',
              paymentDateIso: futurePayIso,
              lastDatePriorIso: '2026-11-13',
              ratePerQuota: 0.81,
              label: 'RENDIMENTO',
              relatedTo: 'Outubro-2026/2026',
              isinCode: 'BRBTLGCTF000',
            ),
          ],
        },
      );
      expect(res1.scheduledCount, 1);
      expect(store.investDividendCategory, 'Investimentos (+) › Dividendos');
      final divOp = store.db.investOps
          .firstWhere((o) => o.type == InvestOpType.fiiYield);
      expect(divOp.totalCents, 8100); // 100 cotas * 0,81
      final divTx = store.db.txs.firstWhere((t) => t.id == divOp.linkedTxId);
      expect(divTx.cat, 'Investimentos (+) › Dividendos');
      expect(divTx.rec, isFalse);

      // Segunda execução deduplica e não agenda novamente
      final res2 = await store.syncAndScheduleFiiDividends(
        preloadedEvents: {
          'btlg': [
            FiiDividendEvent(
              ticker: 'BTLG11',
              paymentDateIso: futurePayIso,
              lastDatePriorIso: '2026-11-13',
              ratePerQuota: 0.81,
              label: 'RENDIMENTO',
              relatedTo: 'Outubro-2026/2026',
              isinCode: 'BRBTLGCTF000',
            ),
          ],
        },
      );
      expect(res2.scheduledCount, 0);
      expect(res2.skippedCount, 1);
    });

    test('parseB3StockDividendsJson filtra ISIN da ação e agenda Dividendo + JCP (15% IR) na mesma data', () async {
      const sampleStockJson = '''
      [
        {
          "code": "PETR",
          "cashDividends": [
            {
              "assetIssued": "BRPETRACNOR9",
              "paymentDate": "21/12/2026",
              "rate": "0,50000000000",
              "relatedTo": "Anual/2026",
              "approvedOn": "06/08/2026",
              "isinCode": "BRPETRACNOR9",
              "label": "DIVIDENDO",
              "lastDatePrior": "21/08/2026"
            },
            {
              "assetIssued": "BRPETRACNPR6",
              "paymentDate": "21/12/2026",
              "rate": "0,50000000000",
              "relatedTo": "Anual/2026",
              "approvedOn": "06/08/2026",
              "isinCode": "BRPETRACNPR6",
              "label": "DIVIDENDO",
              "lastDatePrior": "21/08/2026"
            },
            {
              "assetIssued": "BRPETRACNPR6",
              "paymentDate": "21/12/2026",
              "rate": "0,20000000000",
              "relatedTo": "Anual/2026",
              "approvedOn": "06/08/2026",
              "isinCode": "BRPETRACNPR6",
              "label": "JRS CAP PROPRIO",
              "lastDatePrior": "21/08/2026"
            }
          ]
        }
      ]
      ''';
      final parsedPetr4 = InvestmentQuoteService.parseB3StockDividendsJson(
        'PETR4',
        sampleStockJson,
      );
      expect(parsedPetr4.length, 2); // Apenas BRPETRACNPR6 (PN), ignora ACNOR (ON)
      expect(parsedPetr4.where((e) => e.isDividend).length, 1);
      expect(parsedPetr4.where((e) => e.isJcp).length, 1);

      final store = MoneyStore(autoBoot: false);
      store.db = Database(
        accounts: [
          Account(id: 'xp', name: 'XP', type: 'Investimento', opening: 0),
        ],
      );
      final petr4 = InvestAsset(
        id: 'petr4',
        ticker: 'PETR4',
        name: 'Petrobras PN',
        assetClass: InvestAssetClass.stock,
        accountId: 'xp',
      );
      store.addOrUpdateInvestAsset(petr4);
      store.addInvestOperation(
        InvestOperation(
          id: 'buy_petr4',
          assetId: 'petr4',
          accountId: 'xp',
          type: InvestOpType.buy,
          date: '2026-08-10',
          quantity: 100,
          unitPriceCents: 3800,
          totalCents: 380000,
        ),
        affectAccountCash: false,
      );

      final futurePay = DateTime.now().add(const Duration(days: 10));
      final futurePayIso =
          '${futurePay.year}-${futurePay.month.toString().padLeft(2, '0')}-${futurePay.day.toString().padLeft(2, '0')}';

      final res = await store.syncAndScheduleFiiDividends(
        preloadedEvents: {
          'petr4': [
            FiiDividendEvent(
              ticker: 'PETR4',
              paymentDateIso: futurePayIso,
              lastDatePriorIso: '2026-08-21',
              ratePerQuota: 0.50,
              label: 'DIVIDENDO',
              relatedTo: 'Anual/2026',
              isinCode: 'BRPETRACNPR6',
            ),
            FiiDividendEvent(
              ticker: 'PETR4',
              paymentDateIso: futurePayIso,
              lastDatePriorIso: '2026-08-21',
              ratePerQuota: 0.20,
              label: 'JRS CAP PROPRIO',
              relatedTo: 'Anual/2026',
              isinCode: 'BRPETRACNPR6',
            ),
          ],
        },
      );
      expect(res.scheduledCount, 2);
      final divOp = store.db.investOps
          .firstWhere((o) => o.type == InvestOpType.dividend);
      final jcpOp =
          store.db.investOps.firstWhere((o) => o.type == InvestOpType.jcp);
      expect(divOp.totalCents, 5000); // 100 * 0,50
      expect(jcpOp.taxCents, 300); // 15% de R$ 20,00 = R$ 3,00
      expect(jcpOp.totalCents, 1700); // R$ 17,00 líquido na conta
    });

    test('InvestmentInsightsEngine analisa diversificação, IR, vencimento e alimenta contexto da IA Local', () {
      final store = MoneyStore(autoBoot: false);
      store.db = Database(
        accounts: [
          Account(
            id: 'inv1',
            name: 'XP',
            type: 'Investimento',
            opening: 300000, // R$ 3.000 caixa livre
          ),
        ],
        investAssets: [
          InvestAsset(
            id: 'a1',
            ticker: 'PETR4',
            name: 'Petrobras',
            assetClass: InvestAssetClass.stock,
            accountId: 'inv1',
            currentPriceCents: 4200,
          ),
          InvestAsset(
            id: 'cdb1',
            ticker: 'CDB 110% CDI',
            name: 'CDB Vencimento Próximo',
            assetClass: InvestAssetClass.fixedIncome,
            subType: 'CDB',
            accountId: 'inv1',
            indexer: InvestFixedIncomeIndexer.cdi,
            ratePct: 110.0,
            maturityDate: '2026-12-20',
          ),
        ],
        investOps: [
          InvestOperation(
            id: 'op1',
            assetId: 'a1',
            accountId: 'inv1',
            type: InvestOpType.buy,
            date: '2026-01-10',
            quantity: 100,
            unitPriceCents: 3000,
            totalCents: 300000,
          ),
          InvestOperation(
            id: 'op2',
            assetId: 'cdb1',
            accountId: 'inv1',
            type: InvestOpType.buy,
            date: '2026-06-10', // 169 dias até 2026-11-26 -> faltam 12 dias para 181d (20%)
            quantity: 1,
            unitPriceCents: 100000,
            totalCents: 100000,
          ),
          InvestOperation(
            id: 'op3',
            assetId: 'a1',
            accountId: 'inv1',
            type: InvestOpType.dividend,
            date: '2026-05-01',
            quantity: 100,
            unitPriceCents: 150,
            totalCents: 15000,
          ),
        ],
      );

      final summary = store.portfolioSummary();
      final cashBal = store.investmentCashBalance();
      final report = InvestmentInsightsEngine.analyze(
        summary: summary,
        cashBalanceCents: cashBal,
        baseCurrency: 'BRL',
        asOfDateIso: '2026-11-26',
      );

      expect(report.diversificationScore, inInclusiveRange(10, 100));
      expect(report.fixedIncomeByIndexer.containsKey('CDI / Selic'), isTrue);
      // Concentração > 40% em PETR4, queda de alíquota de IR em 12d, vencimento <= 90d, caixa livre e proventos
      expect(report.insights.any((i) => i.id == 'conc_asset_crit'), isTrue);
      expect(report.insights.any((i) => i.id == 'ir_drop_cdb1'), isTrue);
      expect(report.insights.any((i) => i.id == 'mat_cdb1'), isTrue);
      expect(report.insights.any((i) => i.id == 'idle_cash'), isTrue);
      expect(report.insights.any((i) => i.id == 'passive_income'), isTrue);

      final aiSnapshot =
          FinancialInsightsEngine.buildCompactContextSnapshot(store);
      expect(aiSnapshot.containsKey('investments'), isTrue);
      expect(aiSnapshot['patrimony']['investmentsGross'], isNotNull);
      expect(aiSnapshot['patrimony']['consolidatedTotal'], isNotNull);
      expect(
        aiSnapshot['patrimony']['totalReal'],
        aiSnapshot['patrimony']['consolidatedTotal'],
      );
      final offlineSummary =
          FinancialInsightsEngine.generateOfflineDiagnosticMarkdown(
        store,
        topic: 'overview',
      );
      expect(offlineSummary, contains('Carteira de Investimentos'));
      expect(offlineSummary, contains('Patrimônio Real Consolidado'));
    });

    test('Contas Caixinha e Cofrinhos integram kAccountTypes e saldo total sem contar como caixa de corretora', () {
      expect(kAccountTypes, containsAll(['Caixinha', 'Cofrinhos']));
      expect(isSavingsOrReserveAccountType('Poupança'), isTrue);
      expect(isSavingsOrReserveAccountType('Caixinha'), isTrue);
      expect(isSavingsOrReserveAccountType('Cofrinhos'), isTrue);
      expect(isSavingsOrReserveAccountType('Investimento'), isFalse);

      final store = MoneyStore(autoBoot: false);
      store.db = Database(
        accounts: [
          Account(id: 'c1', name: 'Caixinha Nubank', type: 'Caixinha', opening: 150000),
          Account(id: 'c2', name: 'Cofrinho Inter', type: 'Cofrinhos', opening: 250000),
          Account(id: 'i1', name: 'XP', type: 'Investimento', opening: 100000),
        ],
      );
      expect(store.investmentCashBalance(), 100000);
      expect(store.totalBalance(predicted: false), 500000);
    });
  });
}

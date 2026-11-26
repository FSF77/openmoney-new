import 'package:flutter_test/flutter_test.dart';
import 'package:openmoney/models/openmoney_models.dart';
import 'package:openmoney/services/cash_flow_engine.dart';
import 'package:openmoney/services/investment_engine.dart';
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

      // Provento usa categoria configurável padrão 'Investimentos (-) › Rendimentos'
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
      expect(store.db.txs.last.cat, 'Investimentos (-) › Rendimentos');
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
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmoney/models/investment_models.dart';
import 'package:openmoney/store/money_store.dart';
import 'package:openmoney/ui/views/charts_dashboard_view.dart';

void main() {
  Future<void> pump(WidgetTester t, MoneyStore store, Size size) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: ChartsDashboardView(store: store)),
    ));
    await t.pump();
  }

  testWidgets('renderiza base vazia (desktop e mobile)', (t) async {
    final store = MoneyStore(autoBoot: false);
    await pump(t, store, const Size(1400, 1000));
    expect(find.text('Patrimônio líquido'), findsOneWidget);
    await pump(t, store, const Size(390, 900));
    expect(find.text('Saúde financeira'), findsOneWidget);
    expect(tester(t), isNull);
  });

  testWidgets('troca de período não quebra e suporta Todo período', (t) async {
    final store = MoneyStore(autoBoot: false);
    store.saveAccount(
      name: 'CC',
      type: 'Corrente',
      openingCents: 1000,
      closeDay: 0,
      dueDay: 0,
      payAccId: '',
    );
    await pump(t, store, const Size(1400, 1000));
    await t.tap(find.text('12M'));
    await t.pump();
    await t.tap(find.text('Ano anterior'));
    await t.pump();
    await t.tap(find.text('Todo período'));
    await t.pump();
    expect(find.text('Receitas'), findsOneWidget);
    await t.tap(find.text('Mês'));
    await t.pump();
    expect(find.byTooltip('Mês anterior'), findsOneWidget);
    expect(find.byTooltip('Próximo mês'), findsOneWidget);
    await t.tap(find.byTooltip('Mês anterior'));
    await t.pump();
  });

  testWidgets(
      'exibe graficos de investimentos, liquidez imediata e alterna visoes (desktop e mobile)',
      (t) async {
    final store = MoneyStore(autoBoot: false);
    store.saveAccount(
      name: 'CC Principal',
      type: 'Corrente',
      openingCents: 300000,
      closeDay: 0,
      dueDay: 0,
      payAccId: '',
    );
    store.saveAccount(
      name: 'Caixinha Reserva',
      type: 'Caixinha',
      openingCents: 200000,
      closeDay: 0,
      dueDay: 0,
      payAccId: '',
    );
    store.saveAccount(
      name: 'Corretora XP',
      type: 'Investimento',
      openingCents: 100000,
      closeDay: 0,
      dueDay: 0,
      payAccId: '',
    );
    final ccId = store.db.accounts
        .firstWhere((a) => a.name == 'CC Principal')
        .id;
    final brokerId = store.db.accounts
        .firstWhere((a) => a.name == 'Corretora XP')
        .id;

    final ym = store.month;
    store.addTransaction(
      accId: ccId,
      date: '$ym-05',
      payee: 'Mercado',
      catSelection: 'Alimentação',
      memo: '',
      signedAmt: -100000,
    );

    final petr = InvestAsset(
      ticker: 'PETR4',
      name: 'Petrobras PN',
      assetClass: InvestAssetClass.stock,
      accountId: brokerId,
      currentPriceCents: 3800,
      manualPrice: true,
    );
    final cdb = InvestAsset(
      ticker: 'CDB-XP',
      name: 'CDB XP 110% CDI',
      assetClass: InvestAssetClass.fixedIncome,
      accountId: brokerId,
      indexer: InvestFixedIncomeIndexer.cdi,
      ratePct: 110,
      maturityDate: '2028-06-15',
      currentPriceCents: 105000,
      manualPrice: true,
    );
    store.addOrUpdateInvestAsset(petr);
    store.addOrUpdateInvestAsset(cdb);

    store.addInvestOperation(
      InvestOperation(
        assetId: petr.id,
        accountId: brokerId,
        type: InvestOpType.buy,
        date: '$ym-02',
        quantity: 10,
        unitPriceCents: 3500,
      ),
      affectAccountCash: false,
    );
    store.addInvestOperation(
      InvestOperation(
        assetId: cdb.id,
        accountId: brokerId,
        type: InvestOpType.buy,
        date: '$ym-03',
        quantity: 1,
        unitPriceCents: 100000,
      ),
      affectAccountCash: false,
    );
    store.addInvestOperation(
      InvestOperation(
        assetId: petr.id,
        accountId: brokerId,
        type: InvestOpType.dividend,
        date: '$ym-10',
        quantity: 10,
        unitPriceCents: 150,
        totalCents: 1500,
      ),
      affectAccountCash: false,
    );

    await pump(t, store, const Size(1400, 1000));
    expect(find.textContaining('Liquidez imediata:'), findsOneWidget);
    expect(find.text('Carteira investida'), findsOneWidget);
    expect(find.text('Alocação da carteira'), findsOneWidget);
    expect(find.text('Proventos mensais'), findsOneWidget);
    expect(find.text('Aplicado × Valor atual por classe'), findsOneWidget);
    expect(
        find.text('Escada de vencimentos (RF & Tesouro)'), findsOneWidget);

    await t.tap(find.text('Finanças'));
    await t.pump();
    expect(find.text('Receitas'), findsOneWidget);
    expect(find.text('Carteira investida'), findsNothing);

    await t.tap(find.text('Investimentos'));
    await t.pump();
    expect(find.text('Receitas'), findsNothing);
    expect(find.text('Carteira investida'), findsOneWidget);
    expect(find.text('Proventos mensais'), findsOneWidget);

    await t.tap(find.text('Por Corretora'));
    await t.pump();
    await t.tap(find.text('Indexador RF'));
    await t.pump();
    expect(tester(t), isNull);

    await pump(t, store, const Size(390, 844));
    expect(find.text('Carteira investida'), findsOneWidget);
    expect(tester(t), isNull);
  });
}

Object? tester(WidgetTester t) => t.takeException();

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmoney/models/openmoney_models.dart';
import 'package:openmoney/store/money_store.dart';
import 'package:openmoney/ui/views/investments_view.dart';

void main() {
  MoneyStore buildSampleStore() {
    final store = MoneyStore(autoBoot: false);
    store.db = Database(
      accounts: [
        Account(
          id: 'inv1',
          name: 'XP Investimentos',
          type: 'Investimento',
          opening: 500000,
        ),
        Account(
          id: 'inv2',
          name: 'BTG Pactual',
          type: 'Investimento',
          opening: 200000,
        ),
      ],
      investAssets: [
        InvestAsset(
          id: 'a1',
          accountId: 'inv1',
          ticker: 'PETR4',
          name: 'Petrobras PN',
          assetClass: InvestAssetClass.stock,
          currentPriceCents: 3800,
        ),
        InvestAsset(
          id: 'a2',
          accountId: 'inv2',
          ticker: 'BTLG11',
          name: 'BTG Pactual Logística FII',
          assetClass: InvestAssetClass.fii,
          currentPriceCents: 10150,
        ),
        InvestAsset(
          id: 'a3',
          accountId: 'inv1',
          ticker: 'CDB 110% CDI',
          name: 'CDB Banco Inter Liquidez Diária',
          assetClass: InvestAssetClass.fixedIncome,
          subType: 'CDB',
          indexer: InvestFixedIncomeIndexer.cdi,
          ratePct: 110.0,
        ),
        InvestAsset(
          id: 'a4',
          accountId: 'inv1',
          ticker: 'TESOURO IPCA+ 2029 / IPCA + 7,89%',
          name: 'Tesouro IPCA+ 2029',
          assetClass: InvestAssetClass.tesouro,
          subType: 'Tesouro IPCA+',
          indexer: InvestFixedIncomeIndexer.ipca,
          ratePct: 7.89,
          maturityDate: '2029-05-15',
          currentPriceCents: 401250,
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
          unitPriceCents: 3500,
          totalCents: 350000,
        ),
        InvestOperation(
          id: 'op2',
          assetId: 'a2',
          accountId: 'inv2',
          type: InvestOpType.buy,
          date: '2026-02-15',
          quantity: 20,
          unitPriceCents: 10000,
          totalCents: 200000,
        ),
        InvestOperation(
          id: 'op3',
          assetId: 'a3',
          accountId: 'inv1',
          type: InvestOpType.buy,
          date: '2026-03-01',
          quantity: 1,
          unitPriceCents: 500000,
          totalCents: 500000,
        ),
        InvestOperation(
          id: 'op4',
          assetId: 'a4',
          accountId: 'inv1',
          type: InvestOpType.buy,
          date: '2025-12-26',
          quantity: 1,
          unitPriceCents: 355132,
          totalCents: 355132,
        ),
      ],
    );
    return store;
  }

  Future<void> pumpInvestments(
      WidgetTester t, MoneyStore store, Size size) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);

    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: InvestmentsView(store: store),
      ),
    ));
    await t.pump();
  }

  testWidgets(
      'renderiza InvestmentsView em mobile (390x844) com KPIs 2x2, 6 botões com Tooltip e filtros colapsáveis',
      (t) async {
    final store = buildSampleStore();
    await pumpInvestments(t, store, const Size(390, 844));

    expect(t.takeException(), isNull);
    expect(find.text('Investimentos'), findsOneWidget);

    // Todos os 7 botões superiores com Tooltip presentes
    expect(find.byTooltip('Nova Operação'), findsOneWidget);
    expect(find.byTooltip('Novo Ativo'), findsOneWidget);
    expect(find.byTooltip('Importar B3'), findsOneWidget);
    expect(find.byTooltip('Atualizar Cotações'), findsOneWidget);
    expect(find.byTooltip('Agendar Proventos B3 (FIIs e Ações)'), findsOneWidget);
    expect(find.byTooltip('Exportar PDF'), findsOneWidget);
    expect(find.byTooltip('Exportar CSV'), findsOneWidget);

    // KPIs compactos lado a lado (grade 2x2) e rodapé de totais
    expect(find.text('Patrimônio'), findsOneWidget);
    expect(find.text('Aplicado'), findsOneWidget);
    expect(find.text('Rentabilidade'), findsNWidgets(2));
    expect(find.text('Realiz. + Prov.'), findsOneWidget);

    // Rodapé fixo de totais visível
    expect(find.text('Totais (4 ativos)'), findsOneWidget);

    // No mobile, barra de filtros inicia recolhida e expande ao tocar no botão
    expect(find.text('Ocultar zerados'), findsNothing);
    await t.tap(find.byTooltip('Mostrar filtros'));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.text('Ocultar zerados'), findsOneWidget);
    expect(find.text('Corretora'), findsOneWidget);

    // Filtrar por Ações atualiza o rodapé fixo
    await t.tap(find.text('Ações'));
    await t.pump();
    expect(find.text('Totais (1 ativo)'), findsOneWidget);

    // Abas separadas Renda Fixa e Tesouro Direto sem overflow no mobile
    final rfTab = find.descendant(
        of: find.byType(TabBar), matching: find.text('Renda Fixa'));
    await t.ensureVisible(rfTab);
    await t.tap(rfTab);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.textContaining('CDB 110% CDI'), findsOneWidget);

    final tesouroTab = find.descendant(
        of: find.byType(TabBar), matching: find.text('Tesouro Direto'));
    await t.ensureVisible(tesouroTab);
    await t.tap(tesouroTab);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.textContaining('TESOURO IPCA+ 2029'), findsOneWidget);
  });

  testWidgets(
      'renderiza InvestmentsView em desktop (1024x768) com barra horizontal, cabeçalho fixo e sem overflow',
      (t) async {
    final store = buildSampleStore();
    await pumpInvestments(t, store, const Size(1024, 768));

    expect(t.takeException(), isNull);
    expect(find.byType(Scrollbar), findsNWidgets(2));
    expect(find.text('Ativo'), findsAtLeastNWidgets(1));
    expect(find.text('PM Compra'), findsOneWidget);
    expect(find.text('PM Venda'), findsOneWidget);
    expect(find.text('Proventos'), findsOneWidget);
    expect(find.text('Ocultar zerados'), findsOneWidget);

    // Tocar em Exportar CSV abre diálogo com opções Consolidado e Detalhado
    await t.tap(find.byTooltip('Exportar CSV'));
    await t.pumpAndSettle();
    expect(find.text('Exportar Investimentos (CSV)'), findsOneWidget);
    expect(find.text('Posição Consolidada'), findsOneWidget);
    expect(find.text('Operações Detalhadas'), findsOneWidget);
  });

  testWidgets(
      'desktop largo (1400x768) oculta barra horizontal e mantém cabeçalho fixo ao rolar',
      (t) async {
    final store = buildSampleStore();
    for (int i = 1; i <= 25; i++) {
      final id = 'extra_$i';
      store.db.investAssets.add(InvestAsset(
        id: id,
        accountId: 'inv1',
        ticker: 'ZZZ${i.toString().padLeft(2, '0')}3',
        name: 'Ativo Extra $i',
        assetClass: InvestAssetClass.stock,
        currentPriceCents: 2500,
      ));
      store.db.investOps.add(InvestOperation(
        id: 'op_extra_$i',
        assetId: id,
        accountId: 'inv1',
        type: InvestOpType.buy,
        date: '2026-03-10',
        quantity: 10,
        unitPriceCents: 2000,
        totalCents: 20000,
      ));
    }

    await pumpInvestments(t, store, const Size(1400, 768));

    expect(t.takeException(), isNull);
    // Sem barra horizontal quando tudo cabe na largura da tela
    expect(find.byType(Scrollbar), findsOneWidget);
    final headerAtivoFinder = find.text('Ativo').last;
    expect(headerAtivoFinder, findsOneWidget);
    expect(find.text('PM Compra'), findsOneWidget);

    final headerTopBefore = t.getTopLeft(headerAtivoFinder).dy;

    await t.drag(find.byType(ListView), const Offset(0, -450));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    expect(headerAtivoFinder, findsOneWidget);
    expect(t.getTopLeft(headerAtivoFinder).dy, equals(headerTopBefore));
  });

  testWidgets(
      'redimensionamento entre larguras críticas com barra lateral não gera overflow',
      (t) async {
    final store = buildSampleStore();
    for (final w in [360.0, 560.0, 620.0, 720.0, 900.0, 1024.0, 1120.0, 1180.0, 1250.0, 1400.0]) {
      t.view.physicalSize = Size(w + 240, 820);
      t.view.devicePixelRatio = 1;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              const SizedBox(width: 240),
              Expanded(child: InvestmentsView(store: store)),
            ],
          ),
        ),
      ));
      await t.pump();
      expect(t.takeException(), isNull, reason: 'Overflow na largura útil $w');
    }
    t.view.resetPhysicalSize();
  });
}

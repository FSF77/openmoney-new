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

    // KPIs compactos lado a lado (grade 2x2)
    expect(find.text('Patrimônio'), findsOneWidget);
    expect(find.text('Aplicado'), findsOneWidget);
    expect(find.text('Rentabilidade'), findsOneWidget);
    expect(find.text('Realiz. + Prov.'), findsOneWidget);

    // No mobile, barra de filtros inicia recolhida e expande ao tocar no botão
    expect(find.text('Ocultar zerados'), findsNothing);
    await t.tap(find.byTooltip('Mostrar filtros'));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.text('Ocultar zerados'), findsOneWidget);
    expect(find.text('Corretora'), findsOneWidget);
  });

  testWidgets(
      'renderiza InvestmentsView em desktop (1024x768) com tabela, scrollbars e sem overflow',
      (t) async {
    final store = buildSampleStore();
    await pumpInvestments(t, store, const Size(1024, 768));

    expect(t.takeException(), isNull);
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.byType(Scrollbar), findsNWidgets(2));
    expect(find.text('Ocultar zerados'), findsOneWidget);

    // Tocar em Exportar CSV abre diálogo com opções Consolidado e Detalhado
    await t.tap(find.byTooltip('Exportar CSV'));
    await t.pumpAndSettle();
    expect(find.text('Exportar Investimentos (CSV)'), findsOneWidget);
    expect(find.text('Posição Consolidada'), findsOneWidget);
    expect(find.text('Operações Detalhadas'), findsOneWidget);
  });
}

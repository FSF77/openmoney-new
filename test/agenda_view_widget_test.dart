import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmoney/models/openmoney_models.dart';
import 'package:openmoney/services/agenda_engine.dart';
import 'package:openmoney/store/money_store.dart';
import 'package:openmoney/ui/views/agenda_view.dart';

void main() {
  Future<void> pumpAgenda(WidgetTester t, MoneyStore store, Size size) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);

    await t.pumpWidget(MaterialApp(
      home: AgendaView(store: store),
    ));
    await t.pump();
  }

  testWidgets('renderiza tela da Agenda em Desktop com cabeçalho, filtros e resumo', (t) async {
    final store = MoneyStore(autoBoot: false);
    store.db = Database(
      accounts: [
        Account(id: 'bank', name: 'Banco Inter', type: 'Corrente', opening: 100000),
      ],
      txs: [
        Transaction(
          id: 'tx1',
          acc: 'bank',
          date: todayISO(),
          payee: 'Condomínio Mensal',
          cat: 'Moradia',
          amt: -35000,
          rec: false,
        ),
      ],
    );

    await pumpAgenda(t, store, const Size(1280, 800));

    // Cabeçalho e botões de ação direta
    expect(find.text('Agenda'), findsOneWidget);
    expect(find.text('Hoje'), findsOneWidget);
    expect(find.text('Nova Despesa'), findsOneWidget);
    expect(find.text('Nova Receita'), findsOneWidget);
    expect(find.text('Transferência'), findsOneWidget);

    // Filtros por chips
    expect(find.text('Contas e faturas'), findsOneWidget);
    expect(find.text('Receitas previstas'), findsOneWidget);
    expect(find.text('Concluídos'), findsOneWidget);
    expect(find.text('Como funciona'), findsOneWidget);
    expect(find.text('Imprimir'), findsOneWidget);

    // Cartão de resumo e item
    expect(find.textContaining('Condomínio Mensal'), findsWidgets);

    // Clicar no número do dia abre o diálogo de lançamentos daquele dia
    final dayNum = DateTime.now().day.toString();
    final dayTarget = find.text(dayNum).first;
    await t.tap(dayTarget);
    await t.pumpAndSettle();

    expect(find.textContaining('Dia '), findsOneWidget);
    expect(find.text('Fechar'), findsOneWidget);
  });

  testWidgets('renderiza tela da Agenda em modo Mobile responsivo', (t) async {
    final store = MoneyStore(autoBoot: false);
    await pumpAgenda(t, store, const Size(390, 844));

    expect(find.text('Agenda'), findsOneWidget);
    expect(find.byTooltip('Registrar Nova Despesa'), findsOneWidget);
    expect(find.byTooltip('Registrar Nova Receita'), findsOneWidget);
    expect(find.byTooltip('Registrar Nova Transferência'), findsOneWidget);
  });

  testWidgets('título de Renda Fixa com vencimento no mês aparece na Agenda e abre diálogo com Resgatar', (t) async {
    final store = MoneyStore(autoBoot: false);
    final today = DateTime.now();
    final ym = '${today.year}-${today.month.toString().padLeft(2, '0')}';
    final matIso = '$ym-15';

    store.db = Database(
      accounts: [
        Account(id: 'inv1', name: 'XP Investimentos', type: 'Investimento', opening: 0),
      ],
      investAssets: [
        InvestAsset(
          id: 'cdb1',
          accountId: 'inv1',
          ticker: 'CDB-XP-2026',
          name: 'CDB XP 110% CDI',
          assetClass: InvestAssetClass.fixedIncome,
          indexer: InvestFixedIncomeIndexer.cdi,
          ratePct: 110,
          maturityDate: matIso,
          currentPriceCents: 105000,
        ),
      ],
      investOps: [
        InvestOperation(
          id: 'op1',
          assetId: 'cdb1',
          accountId: 'inv1',
          type: InvestOpType.buy,
          date: '2026-01-10',
          quantity: 1,
          unitPriceCents: 100000,
          totalCents: 100000,
        ),
      ],
    );

    final entries = AgendaEngine.generateMonthEntries(
      store: store,
      month: ym,
    );
    final matEntry = entries.where((e) => e.isInvestmentMaturity).toList();
    expect(matEntry.length, 1);
    expect(matEntry.first.title, 'Vencimento CDB-XP-2026');
    expect(matEntry.first.date, matIso);

    await pumpAgenda(t, store, const Size(1280, 900));
    expect(find.textContaining('Vencimento CDB-XP-2026'), findsWidgets);
  });
}

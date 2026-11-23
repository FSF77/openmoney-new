import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmoney/models/openmoney_models.dart';
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
  });

  testWidgets('renderiza tela da Agenda em modo Mobile responsivo', (t) async {
    final store = MoneyStore(autoBoot: false);
    await pumpAgenda(t, store, const Size(390, 844));

    expect(find.text('Agenda'), findsOneWidget);
    expect(find.byTooltip('Registrar Nova Despesa'), findsOneWidget);
    expect(find.byTooltip('Registrar Nova Receita'), findsOneWidget);
    expect(find.byTooltip('Registrar Nova Transferência'), findsOneWidget);
  });
}

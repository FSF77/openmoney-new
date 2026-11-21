import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}

Object? tester(WidgetTester t) => t.takeException();

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmoney/models/openmoney_models.dart';
import 'package:openmoney/services/category_icon_registry.dart';
import 'package:openmoney/store/money_store.dart';
import 'package:openmoney/ui/modals/category_icon_picker_dialog.dart';
import 'package:openmoney/ui/widgets/category_select_form_field.dart';

void main() {
  testWidgets('CategoryIconBadge renders in light and dark themes', (tester) async {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: CategoryIconBadge(
              category: CategoryItem(
                name: 'Alimentação',
                type: 'Despesa',
                icon: 'restaurant',
                color: 'orange',
              ),
              size: 24,
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.restaurant_rounded), findsOneWidget);
    }
  });

  testWidgets('CategorySelectFormField shows badge for selected category and menu items',
      (tester) async {
    final store = MoneyStore(autoBoot: false);
    store.db = Database(
      v: 7,
      accounts: [
        Account(id: 'a1', name: 'Nubank', type: 'Corrente', opening: 0),
      ],
      cats: [
        CategoryItem(
          name: 'Alimentação',
          type: 'Despesa',
          icon: 'restaurant',
          color: 'orange',
        ),
        CategoryItem(
          name: 'Mercado',
          parent: 'Alimentação',
          type: 'Despesa',
        ),
      ],
      txs: [],
      recs: [],
      budgets: {},
    );
    store.rebuildIndexes();

    String selected = 'Alimentação$kCategorySep' 'Mercado';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (ctx, setState) => CategorySelectFormField(
              store: store,
              categoryType: 'Despesa',
              currentSelection: selected,
              onChanged: (v) => setState(() => selected = v),
            ),
          ),
        ),
      ),
    );

    // Closed field displays inherited restaurant icon
    expect(find.byIcon(Icons.restaurant_rounded), findsOneWidget);
    expect(find.text('↳ Mercado'), findsOneWidget);

    // Open popup menu
    await tester.tap(find.byType(CategorySelectFormField));
    await tester.pumpAndSettle();

    expect(find.text('Alimentação'), findsOneWidget);
    expect(find.text('↳ Mercado'), findsWidgets);
  });

  testWidgets('CategoryIconPickerDialog filters icons and returns selection',
      (tester) async {
    ({String? icon, String? color})? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                result = await showCategoryIconPickerDialog(
                  ctx,
                  categoryName: 'Meus Pets',
                  categoryType: 'Despesa',
                );
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'cachorro');
    await tester.pumpAndSettle();

    expect(find.text('Pets'), findsOneWidget);
    await tester.tap(find.text('Pets'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.icon, 'pets');
  });
}

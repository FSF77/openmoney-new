import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmoney/models/openmoney_models.dart';
import 'package:openmoney/services/category_icon_registry.dart';
import 'package:openmoney/store/money_store.dart';

void main() {
  group('CategoryItem serialization & backward compatibility', () {
    test('fromJson handles legacy string and map without icon/color', () {
      final legacyStr = CategoryItem.fromJson('Salário');
      expect(legacyStr.name, 'Salário');
      expect(legacyStr.type, 'Receita');
      expect(legacyStr.icon, isNull);
      expect(legacyStr.color, isNull);

      final legacyMap = CategoryItem.fromJson({
        'name': 'Mercado',
        'parent': 'Alimentação',
        'type': 'Despesa',
      });
      expect(legacyMap.name, 'Mercado');
      expect(legacyMap.parent, 'Alimentação');
      expect(legacyMap.icon, isNull);
      expect(legacyMap.color, isNull);
    });

    test('toJson omits null/empty icon and color, preserves non-empty', () {
      final withoutVisual = CategoryItem(
        name: 'Teste',
        icon: '  ',
        color: '',
      );
      final jsonEmpty = withoutVisual.toJson();
      expect(jsonEmpty.containsKey('icon'), isFalse);
      expect(jsonEmpty.containsKey('color'), isFalse);

      final withVisual = CategoryItem(
        name: 'Pets',
        icon: 'pets',
        color: 'amber',
      );
      final jsonFilled = withVisual.toJson();
      expect(jsonFilled['icon'], 'pets');
      expect(jsonFilled['color'], 'amber');

      final roundTrip = CategoryItem.fromJson(jsonFilled);
      expect(roundTrip, equals(withVisual));
    });
  });

  group('CategoryIconRegistry resolution & inheritance', () {
    test('auto-matches root categories with and without diacritics', () {
      final food = CategoryIconRegistry.resolve(
        category: CategoryItem(name: 'Alimentação', type: 'Despesa'),
      );
      expect(food.icon, Icons.restaurant_rounded);
      expect(food.colorKey, 'orange');

      final health = CategoryIconRegistry.resolve(
        category: CategoryItem(name: 'Saude', type: 'Despesa'),
      );
      expect(health.icon, Icons.medical_services_rounded);
      expect(health.colorKey, 'red');

      final income = CategoryIconRegistry.resolve(
        category: CategoryItem(name: 'Renda', type: 'Receita'),
      );
      expect(income.icon, Icons.payments_rounded);
      expect(income.colorKey, 'emerald');
    });

    test('subcategory inherits parent icon and color by default', () {
      final parent = CategoryItem(
        name: 'Alimentação',
        type: 'Despesa',
        icon: 'restaurant',
        color: 'orange',
      );
      final sub = CategoryItem(
        name: 'Mercado',
        parent: 'Alimentação',
        type: 'Despesa',
      );

      final resolved = CategoryIconRegistry.resolve(
        category: sub,
        parentCategory: parent,
      );
      expect(resolved.icon, Icons.restaurant_rounded);
      expect(resolved.colorKey, 'orange');
      expect(resolved.isInherited, isTrue);
      expect(resolved.isCustomized, isFalse);
    });

    test('subcategory can override icon and/or color independently', () {
      final parent = CategoryItem(
        name: 'Alimentação',
        type: 'Despesa',
        icon: 'restaurant',
        color: 'orange',
      );

      final subIconOnly = CategoryItem(
        name: 'Mercado',
        parent: 'Alimentação',
        type: 'Despesa',
        icon: 'shopping_cart',
      );
      final resIconOnly = CategoryIconRegistry.resolve(
        category: subIconOnly,
        parentCategory: parent,
      );
      expect(resIconOnly.icon, Icons.shopping_cart_rounded);
      expect(resIconOnly.colorKey, 'orange');
      expect(resIconOnly.isCustomized, isTrue);

      final subBoth = CategoryItem(
        name: 'Padaria',
        parent: 'Alimentação',
        type: 'Despesa',
        icon: 'local_cafe',
        color: 'amber',
      );
      final resBoth = CategoryIconRegistry.resolve(
        category: subBoth,
        parentCategory: parent,
      );
      expect(resBoth.icon, Icons.local_cafe_rounded);
      expect(resBoth.colorKey, 'amber');
      expect(resBoth.isCustomized, isTrue);
    });

    test('detects transfers and falls back cleanly for unknown categories', () {
      final xfer = CategoryIconRegistry.resolve(rawPath: 'xfer:acc1');
      expect(xfer.icon, Icons.swap_horiz_rounded);

      final unknownExp = CategoryIconRegistry.resolve(
        category: CategoryItem(name: 'Coisa Aleatória', type: 'Despesa'),
      );
      expect(unknownExp.icon, Icons.label_outline_rounded);

      final unknownInc = CategoryIconRegistry.resolve(
        category: CategoryItem(name: 'Ganho Extra XYZ', type: 'Receita'),
      );
      expect(unknownInc.icon, Icons.trending_up_rounded);
    });

    test('searchIcons matches Portuguese keywords without diacritics', () {
      final results = CategoryIconRegistry.searchIcons('saude');
      expect(results.any((i) => i.id == 'medical_services'), isTrue);

      final gas = CategoryIconRegistry.searchIcons('gasolina');
      expect(gas.any((i) => i.id == 'local_gas_station'), isTrue);
    });
  });

  group('MoneyStore.saveCategory icon & color persistence', () {
    test('saves, preserves, updates, and clears icon and color', () {
      final store = MoneyStore(autoBoot: false);
      store.db = Database(cats: []);

      final err1 = store.saveCategory(
        name: 'Pets',
        type: 'Despesa',
        icon: 'pets',
        color: 'amber',
      );
      expect(err1, isNull);
      var cat = store.categoryByPath('Pets');
      expect(cat, isNotNull);
      expect(cat!.icon, 'pets');
      expect(cat.color, 'amber');

      // Editing without updateIcon/updateColor preserves existing icon/color
      final err2 = store.saveCategory(
        editingPath: 'Pets',
        name: 'Meus Pets',
        type: 'Despesa',
      );
      expect(err2, isNull);
      cat = store.categoryByPath('Meus Pets');
      expect(cat?.icon, 'pets');
      expect(cat?.color, 'amber');

      // Clearing via updateIcon/updateColor
      final err3 = store.saveCategory(
        editingPath: 'Meus Pets',
        name: 'Meus Pets',
        type: 'Despesa',
        icon: null,
        color: null,
        updateIcon: true,
        updateColor: true,
      );
      expect(err3, isNull);
      cat = store.categoryByPath('Meus Pets');
      expect(cat?.icon, isNull);
      expect(cat?.color, isNull);
    });
  });
}

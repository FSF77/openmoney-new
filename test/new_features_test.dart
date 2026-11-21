import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmoney/models/openmoney_models.dart';
import 'package:openmoney/services/date_validator.dart';
import 'package:openmoney/services/importers_exporters.dart';
import 'package:openmoney/services/math_expression_evaluator.dart';
import 'package:openmoney/store/money_store.dart';
import 'package:openmoney/ui/widgets/date_input_formatter.dart';

void main() {
  group('Item 1: CSV Export Opening Balance (SALDO INICIAL)', () {
    test('Includes SALDO INICIAL row for account with positive opening balance', () {
      final acc = Account(
        id: 'acc1',
        name: 'Banco Itaú',
        type: 'Corrente',
        opening: 150000, // R$ 1.500,00
      );
      final txs = [
        Transaction(
          id: 'tx1',
          acc: 'acc1',
          date: '2026-11-15',
          payee: 'Mercado',
          cat: 'Alimentação',
          memo: 'Compras da semana',
          amt: -20000,
          rec: true,
        ),
      ];

      final csv = CSVExporter.generateCSV(
        transactions: txs,
        accounts: [acc],
        accountFilterId: 'acc1',
      );

      expect(csv, contains('SALDO INICIAL'));
      expect(csv, contains('1500,00'));
      expect(csv, contains('Mercado'));

      // Verifica que a categoria do SALDO INICIAL é vazia
      final lines = csv.split('\r\n');
      final initLine = lines.firstWhere((l) => l.contains('SALDO INICIAL'));
      expect(initLine, contains('"SALDO INICIAL";"";""'));
    });

    test('Includes SALDO INICIAL row for account with negative opening balance', () {
      final acc = Account(
        id: 'acc2',
        name: 'Cheque Especial',
        type: 'Corrente',
        opening: -50000, // -R$ 500,00
      );
      final txs = <Transaction>[];

      final csv = CSVExporter.generateCSV(
        transactions: txs,
        accounts: [acc],
        accountFilterId: 'acc2',
      );

      expect(csv, contains('SALDO INICIAL'));
      expect(csv, contains('-500,00'));
    });

    test('Does not include SALDO INICIAL row when opening balance is zero', () {
      final acc = Account(
        id: 'acc3',
        name: 'Carteira',
        type: 'Dinheiro',
        opening: 0,
      );
      final txs = [
        Transaction(
          id: 'tx1',
          acc: 'acc3',
          date: '2026-11-15',
          payee: 'Pão',
          cat: 'Padaria',
          amt: -1000,
          rec: true,
        ),
      ];

      final csv = CSVExporter.generateCSV(
        transactions: txs,
        accounts: [acc],
        accountFilterId: 'acc3',
      );

      expect(csv, isNot(contains('SALDO INICIAL')));
      expect(csv, contains('Pão'));
    });
  });

  group('Item 2: CSV Account Export and Import', () {
    test('Exports all account fields and imports them back accurately', () {
      final acc1 = Account(
        id: 'acc_itau',
        name: 'Itaú Personalité',
        type: 'Corrente',
        opening: 250000,
        currency: 'BRL',
        favorite: true,
        inactive: false,
        business: 'PF',
        bankCode: '341',
        agency: '1234',
        accountNumber: '56789-0',
        comments: 'Conta principal',
        minBalance: 50000,
        logo: 'itau',
        walletAliases: ['itau_pf', 'cartao_itau'],
      );

      final acc2 = Account(
        id: 'acc_nubank',
        name: 'Nubank Roxinho',
        type: kCardType,
        opening: 0,
        currency: 'BRL',
        favorite: false,
        inactive: false,
        card: CardConfig(closeDay: 5, dueDay: 12, pay: 'acc_itau'),
      );

      final csv = AccountCSVExporter.generateCSV([acc1, acc2]);
      expect(csv, contains('"ID";"Nome";"Tipo";"Saldo Inicial"'));
      expect(csv, contains('Itaú Personalité'));
      expect(csv, contains('341'));
      expect(csv, contains('Nubank Roxinho'));
      expect(csv, contains('acc_itau'));

      // Test parsing back
      final parseResult = AccountCSVImporter.parse(
        content: csv,
        existingAccounts: [],
      );

      expect(parseResult.newAccounts.length, equals(2));
      final importedItau = parseResult.newAccounts.firstWhere((a) => a.id == 'acc_itau');
      expect(importedItau.name, equals('Itaú Personalité'));
      expect(importedItau.bankCode, equals('341'));
      expect(importedItau.agency, equals('1234'));
      expect(importedItau.opening, equals(250000));
      expect(importedItau.favorite, isTrue);
      expect(importedItau.walletAliases, contains('itau_pf'));

      final importedNu = parseResult.newAccounts.firstWhere((a) => a.id == 'acc_nubank');
      expect(importedNu.card?.closeDay, equals(5));
      expect(importedNu.card?.dueDay, equals(12));
      expect(importedNu.card?.pay, equals('acc_itau'));
    });

    test('MoneyStore importAccountsCSVBytes updates existing accounts and adds new ones', () {
      final store = MoneyStore();
      store.db.accounts.clear();
      store.db.accounts.add(
        Account(id: 'a1', name: 'Conta Antiga', type: 'Corrente', opening: 100),
      );

      const csvContent = '"ID";"Nome";"Tipo";"Saldo Inicial";"Moeda";"Favorita"\n'
          '"a1";"Conta Renomeada";"Corrente";"200,00";"BRL";"Sim"\n'
          '"a2";"Conta Nova";"Poupança";"50,00";"BRL";"Não"';

      final bytes = Uint8List.fromList(utf8.encode(csvContent));
      final summary = store.importAccountsCSVBytes(bytes);

      expect(summary.importedCount, equals(2));
      expect(store.db.accounts.length, equals(2));
      final a1 = store.db.accounts.firstWhere((a) => a.id == 'a1');
      expect(a1.name, equals('Conta Renomeada'));
      expect(a1.opening, equals(20000));
      expect(a1.favorite, isTrue);

      final a2 = store.db.accounts.firstWhere((a) => a.id == 'a2');
      expect(a2.name, equals('Conta Nova'));
      expect(a2.opening, equals(5000));
    });
  });

  group('Item 4: Credit Card Invoices Date Format dd/mm/aa', () {
    test('fmtDateShortYear formats ISO yyyy-mm-dd to dd/mm/yy', () {
      expect(fmtDateShortYear('2026-11-10'), equals('10/11/26'));
      expect(fmtDateShortYear('2025-01-05'), equals('05/01/25'));
      expect(fmtDateShortYear('invalid'), equals('invalid'));
    });
  });

  group('Item 5: DateInputFormatter', () {
    final formatter = DateInputFormatter();

    test('Inserts slash after 2 digits and 4 digits', () {
      // 1 digit
      var val = formatter.formatEditUpdate(
        const TextEditingValue(text: ''),
        const TextEditingValue(text: '1', selection: TextSelection.collapsed(offset: 1)),
      );
      expect(val.text, equals('1'));

      // 2 digits -> auto inserts slash
      val = formatter.formatEditUpdate(
        const TextEditingValue(text: '1'),
        const TextEditingValue(text: '12', selection: TextSelection.collapsed(offset: 2)),
      );
      expect(val.text, equals('12/'));

      // 3 digits
      val = formatter.formatEditUpdate(
        const TextEditingValue(text: '12/'),
        const TextEditingValue(text: '12/1', selection: TextSelection.collapsed(offset: 4)),
      );
      expect(val.text, equals('12/1'));

      // 4 digits -> auto inserts second slash
      val = formatter.formatEditUpdate(
        const TextEditingValue(text: '12/1'),
        const TextEditingValue(text: '12/11', selection: TextSelection.collapsed(offset: 5)),
      );
      expect(val.text, equals('12/11/'));

      // Full date
      val = formatter.formatEditUpdate(
        const TextEditingValue(text: '12/11/'),
        const TextEditingValue(text: '12/11/2026', selection: TextSelection.collapsed(offset: 10)),
      );
      expect(val.text, equals('12/11/2026'));
    });

    test('Pasting 8 digits formats to dd/mm/yyyy', () {
      final val = formatter.formatEditUpdate(
        const TextEditingValue(text: ''),
        const TextEditingValue(text: '15112026', selection: TextSelection.collapsed(offset: 8)),
      );
      expect(val.text, equals('15/11/2026'));
    });

    test('Backspace on slash smoothly removes it', () {
      final val = formatter.formatEditUpdate(
        const TextEditingValue(text: '12/'),
        const TextEditingValue(text: '12', selection: TextSelection.collapsed(offset: 2)),
      );
      expect(val.text, equals('1'));
    });
  });

  group('Item 6: MathExpressionEvaluator', () {
    test('hasMathExpression detects math symbols', () {
      expect(MathExpressionEvaluator.hasMathExpression('10 + 10'), isTrue);
      expect(MathExpressionEvaluator.hasMathExpression('100 - 20'), isTrue);
      expect(MathExpressionEvaluator.hasMathExpression('5 * 4'), isTrue);
      expect(MathExpressionEvaluator.hasMathExpression('5 x 4'), isTrue);
      expect(MathExpressionEvaluator.hasMathExpression('20 / 2'), isTrue);
      expect(MathExpressionEvaluator.hasMathExpression('20 ÷ 2'), isTrue);
      expect(MathExpressionEvaluator.hasMathExpression('15,00'), isFalse);
      expect(MathExpressionEvaluator.hasMathExpression('-15,00'), isFalse);
      expect(MathExpressionEvaluator.hasMathExpression(''), isFalse);
    });

    test('evaluate handles arithmetic operations with precedence', () {
      expect(MathExpressionEvaluator.evaluate('10 + 10'), equals(20.0));
      expect(MathExpressionEvaluator.evaluate('10,50 + 2,50'), equals(13.0));
      expect(MathExpressionEvaluator.evaluate('100 - 15,30'), closeTo(84.7, 0.001));
      expect(MathExpressionEvaluator.evaluate('10 * 3 + 5'), equals(35.0));
      expect(MathExpressionEvaluator.evaluate('10 + 3 * 5'), equals(25.0));
      expect(MathExpressionEvaluator.evaluate('50 / 2'), equals(25.0));
      expect(MathExpressionEvaluator.evaluate('(10 + 5) * 2'), equals(30.0));
      expect(MathExpressionEvaluator.evaluate('10 x 2'), equals(20.0));
      expect(MathExpressionEvaluator.evaluate('20 ÷ 4'), equals(5.0));
    });

    test('evaluateToFormatted formats result to Brazilian currency input', () {
      expect(MathExpressionEvaluator.evaluateToFormatted('10 + 10'), equals('20,00'));
      expect(MathExpressionEvaluator.evaluateToFormatted('100 / 4'), equals('25,00'));
      expect(MathExpressionEvaluator.evaluateToFormatted('15,00'), isNull); // not an expression
    });
  });

  group('Item 7: Transaction Date Validation and Range Warnings', () {
    test('Valid date within normal window', () {
      final now = DateTime.now();
      final dayStr = now.day.toString().padLeft(2, '0');
      final monthStr = now.month.toString().padLeft(2, '0');
      final res = validateTransactionDate('$dayStr/$monthStr/${now.year}');
      expect(res.isValid, isTrue);
      expect(res.isWarning, isFalse);
      expect(res.isoDate, equals('${now.year}-$monthStr-$dayStr'));
    });

    test('Rejects invalid calendar dates', () {
      expect(validateTransactionDate('32/01/2026').isValid, isFalse);
      expect(validateTransactionDate('31/02/2026').isValid, isFalse);
      expect(validateTransactionDate('29/02/2025').isValid, isFalse); // Not leap year
      expect(validateTransactionDate('29/02/2024').isValid, isTrue); // Leap year
      expect(validateTransactionDate('31/04/2026').isValid, isFalse); // April has 30 days
      expect(validateTransactionDate('00/05/2026').isValid, isFalse);
      expect(validateTransactionDate('15/13/2026').isValid, isFalse);
      expect(validateTransactionDate('abc').isValid, isFalse);
    });

    test('Warns when date is more than 30 days in the past', () {
      final pastDate = DateTime.now().subtract(const Duration(days: 45));
      final dayStr = pastDate.day.toString().padLeft(2, '0');
      final monthStr = pastDate.month.toString().padLeft(2, '0');
      final res = validateTransactionDate('$dayStr/$monthStr/${pastDate.year}');
      expect(res.isValid, isTrue);
      expect(res.isWarning, isTrue);
      expect(res.warningMessage, contains('mais de 30 dias'));
    });

    test('Warns when date is more than 12 months in the future', () {
      final futureDate = DateTime.now().add(const Duration(days: 400));
      final dayStr = futureDate.day.toString().padLeft(2, '0');
      final monthStr = futureDate.month.toString().padLeft(2, '0');
      final res = validateTransactionDate('$dayStr/$monthStr/${futureDate.year}');
      expect(res.isValid, isTrue);
      expect(res.isWarning, isTrue);
      expect(res.warningMessage, contains('posterior a 12 meses'));
    });

    test('DateInputFormatter clamps impossible days and months during typing', () {
      final formatter = DateInputFormatter();
      // Day 35 clamped to 31
      var val = formatter.formatEditUpdate(
        const TextEditingValue(text: ''),
        const TextEditingValue(text: '35', selection: TextSelection.collapsed(offset: 2)),
      );
      expect(val.text, equals('31/'));

      // Month 15 clamped to 12
      val = formatter.formatEditUpdate(
        const TextEditingValue(text: '15/'),
        const TextEditingValue(text: '15/15', selection: TextSelection.collapsed(offset: 5)),
      );
      expect(val.text, equals('15/12/'));

      // Feb 31 clamped to 29
      val = formatter.formatEditUpdate(
        const TextEditingValue(text: '31/'),
        const TextEditingValue(text: '31/02', selection: TextSelection.collapsed(offset: 5)),
      );
      expect(val.text, equals('29/02/'));
    });
  });

  group('Item 8: Prediction Payees Excluded from Suggestions and Auto-complete', () {
    test('payeeSuggestions and lastCategoryAndType never suggest Previsão items', () {
      final store = MoneyStore();
      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // Seed with accounts and transactions
      store.loadFromJsonString(jsonEncode({
        'v': 7,
        'accounts': [
          {'id': 'a1', 'name': 'Conta Corrente', 'type': 'Corrente', 'opening': 0, 'cur': 'BRL'},
        ],
        'categories': {
          'Despesa': ['Moradia', 'Alimentação'],
          'Receita': ['Salário'],
        },
        'txs': [
          // Normal transactions
          {
            'id': 't1',
            'acc': 'a1',
            'date': todayStr,
            'payee': 'Padaria Central',
            'cat': 'Alimentação',
            'amt': -2500,
            'rec': true,
          },
          // Prediction transactions (with "Previsão" and "Previsao")
          {
            'id': 't2',
            'acc': 'a1',
            'date': todayStr,
            'payee': 'Previsão Aluguel',
            'cat': 'Moradia',
            'amt': -150000,
            'rec': false,
            'auto': true,
          },
          {
            'id': 't3',
            'acc': 'a1',
            'date': todayStr,
            'payee': 'Previsao Salário Extra',
            'cat': 'Salário',
            'amt': 500000,
            'rec': false,
          },
        ],
      }));

      // Search for "Padaria" -> should suggest Padaria Central
      final normalSuggestions = store.payeeSuggestions('Pad', isExpense: true);
      expect(normalSuggestions.any((s) => s.name == 'Padaria Central'), isTrue);

      // Search for "Prev" -> should return empty suggestions (predictions are filtered)
      final prevSuggestions = store.payeeSuggestions('Prev', isExpense: true);
      expect(prevSuggestions.isEmpty, isTrue);

      // lastCategoryAndType for "Previsão Aluguel" -> should be null
      final lastCatPrev = store.lastCategoryAndType('Previsão Aluguel', isExpense: true);
      expect(lastCatPrev, isNull);

      // lastCategoryAndType for "Padaria" -> should return Alimentação
      final lastCatNormal = store.lastCategoryAndType('Padaria', isExpense: true);
      expect(lastCatNormal, isNotNull);
      expect(lastCatNormal?.category, equals('Alimentação'));
    });

    test('payeeSuggestions strips installment numbers like 1/3, 8/12, 7/24 from historical descriptions', () {
      expect(stripInstallmentFromPayee('Amazon 1/3'), equals('Amazon'));
      expect(stripInstallmentFromPayee('Logitech Mouse Bluetooth 8/12'), equals('Logitech Mouse Bluetooth'));
      expect(stripInstallmentFromPayee('Mercado Livre 7/24'), equals('Mercado Livre'));
      expect(stripInstallmentFromPayee('Amazon (2/3)'), equals('Amazon'));
      expect(stripInstallmentFromPayee('Amazon - 01/10'), equals('Amazon'));
      expect(stripInstallmentFromPayee('Loja 24/7'), equals('Loja 24/7'));

      final store = MoneyStore();
      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      store.loadFromJsonString(jsonEncode({
        'v': 7,
        'accounts': [
          {'id': 'a1', 'name': 'Cartão', 'type': 'Cartão de crédito', 'opening': 0, 'cur': 'BRL'},
        ],
        'categories': {
          'Despesa': ['Compras', 'Informática'],
        },
        'txs': [
          {
            'id': 't1',
            'acc': 'a1',
            'date': todayStr,
            'payee': 'Amazon 1/3',
            'cat': 'Compras',
            'amt': -10000,
            'rec': true,
          },
          {
            'id': 't2',
            'acc': 'a1',
            'date': todayStr,
            'payee': 'Amazon 2/3',
            'cat': 'Compras',
            'amt': -10000,
            'rec': true,
          },
          {
            'id': 't3',
            'acc': 'a1',
            'date': todayStr,
            'payee': 'Logitech Mouse Bluetooth 8/12',
            'cat': 'Informática',
            'amt': -4500,
            'rec': true,
          },
          {
            'id': 't4',
            'acc': 'a1',
            'date': todayStr,
            'payee': 'Mercado Livre 7/24',
            'cat': 'Compras',
            'amt': -8900,
            'rec': true,
          },
        ],
      }));

      final amazonSug = store.payeeSuggestions('Ama', isExpense: true);
      expect(amazonSug.length, equals(1));
      expect(amazonSug.first.name, equals('Amazon'));
      expect(amazonSug.first.count, equals(2));

      final logiSug = store.payeeSuggestions('Logi', isExpense: true);
      expect(logiSug.length, equals(1));
      expect(logiSug.first.name, equals('Logitech Mouse Bluetooth'));

      final mlSug = store.payeeSuggestions('Merc', isExpense: true);
      expect(mlSug.length, equals(1));
      expect(mlSug.first.name, equals('Mercado Livre'));
    });
  });
}

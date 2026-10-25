import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmoney/main.dart';
import 'package:openmoney/models/openmoney_models.dart';
import 'package:openmoney/services/cash_flow_engine.dart';
import 'package:openmoney/store/money_store.dart';

void main() {
  group('OpenMoney JSON v6 Schema & Business Rules Parity Tests', () {
    test('1. Preserves 100% exact JSON v6 structure and integer cents', () {
      const sampleJson = '''
{
  "accounts": [
    {
      "id": "acc1",
      "name": "Itaú Uniclass",
      "type": "Corrente",
      "opening": 125050,
      "favorite": true
    },
    {
      "id": "card1",
      "name": "Nubank Ultravioleta",
      "type": "Cartão de crédito",
      "opening": 0,
      "card": {
        "closeDay": 5,
        "dueDay": 12,
        "pay": "acc1"
      },
      "invoices": {
        "2026-10": {
          "close": "2026-10-05",
          "due": "2026-10-12",
          "pay": "acc1",
          "manual": true
        }
      }
    }
  ],
  "cats": [
    {
      "name": "Alimentação",
      "type": "Despesa"
    },
    {
      "name": "Mercado",
      "parent": "Alimentação",
      "type": "Despesa",
      "includeInReports": true
    }
  ],
  "txs": [
    {
      "id": "tx1",
      "acc": "card1",
      "date": "2026-10-03",
      "payee": "Pão de Açúcar (1/3)",
      "cat": "Alimentação › Mercado",
      "memo": "Compra mensal",
      "amt": -45990,
      "rec": true,
      "ik": "2026-10",
      "plan": "p1",
      "pn": 1,
      "pt": 3,
      "createdAt": 1729800000.5
    }
  ],
  "recs": [
    {
      "id": "r1",
      "acc": "acc1",
      "start": "2026-01-10",
      "freq": "monthly",
      "payee": "Condomínio",
      "cat": "Casa › Condomínio",
      "memo": "Boleto",
      "amt": -120000,
      "nextSeq": 11
    }
  ],
  "budgets": {
    "Alimentação › Mercado": 250000
  },
  "v": 6
}
''';

      final decodedMap = jsonDecode(sampleJson) as Map<String, dynamic>;
      final db = Database.fromJson(decodedMap);

      expect(db.v, 6);
      expect(db.accounts.length, 2);
      expect(db.accounts[0].id, 'acc1');
      expect(db.accounts[0].opening, 125050);
      expect(db.accounts[0].isFavorite, true);
      expect(db.accounts[1].card?.closeDay, 5);
      expect(db.accounts[1].card?.dueDay, 12);
      expect(db.accounts[1].invoices?['2026-10']?.manual, true);

      expect(db.txs.length, 1);
      final tx = db.txs.first;
      expect(tx.id, 'tx1');
      expect(tx.amt, -45990);
      expect(tx.ik, '2026-10');
      expect(tx.plan, 'p1');
      expect(tx.pn, 1);
      expect(tx.pt, 3);
      expect(tx.createdAt, 1729800000.5);

      expect(db.budgets['Alimentação › Mercado'], 250000);

      // Re-serialize and verify round-trip fidelity
      final reEncoded = jsonDecode(jsonEncode(db.toJson())) as Map<String, dynamic>;
      final roundTripDb = Database.fromJson(reEncoded);
      expect(roundTripDb.txs.first.amt, -45990);
      expect(roundTripDb.accounts.first.opening, 125050);
      expect(roundTripDb.budgets['Alimentação › Mercado'], 250000);
    });

    test('2. Credit Card Invoice cycle, partial payment and settlement', () {
      final store = MoneyStore(autoBoot: false);
      store.saveAccount(
        name: 'Cartão Visa',
        type: kCardType,
        openingCents: 0,
        closeDay: 10,
        dueDay: 20,
        payAccId: 'a1',
      );
      final cardAcc =
          store.db.accounts.firstWhere((a) => a.type == kCardType);

      // Purchase on day 08 (<= closeDay 10) -> stays in 2026-10
      store.addTransaction(
        accId: cardAcc.id,
        date: '2026-10-08',
        payee: 'Restaurante',
        catSelection: 'Alimentação',
        memo: '',
        signedAmt: -20000, // R$ 200,00
      );

      // Purchase on day 15 (> closeDay 10) -> goes to 2026-11
      store.addTransaction(
        accId: cardAcc.id,
        date: '2026-10-15',
        payee: 'Posto',
        catSelection: 'Transporte › Combustível',
        memo: '',
        signedAmt: -35000, // R$ 350,00
      );

      final octSummary = store.invoiceSummary(cardAcc.id, '2026-10')!;
      expect(octSummary.chargesCents, 20000);
      expect(octSummary.remainingCents, 20000);
      expect(octSummary.isFullyPaid, false);

      final novSummary = store.invoiceSummary(cardAcc.id, '2026-11')!;
      expect(novSummary.chargesCents, 35000);

      // Partial payment of R$ 80,00 on 2026-10 invoice
      store.payInvoice(
        cardId: cardAcc.id,
        invoiceKey: '2026-10',
        amountCents: 8000,
        paymentDate: '2026-10-12',
        sourceAccountId: 'a1',
      );

      final afterPartial = store.invoiceSummary(cardAcc.id, '2026-10')!;
      expect(afterPartial.paymentsCents, 8000);
      expect(afterPartial.remainingCents, 12000);

      // Full remaining payment of R$ 120,00
      store.payInvoice(
        cardId: cardAcc.id,
        invoiceKey: '2026-10',
        amountCents: 12000,
        paymentDate: '2026-10-18',
        sourceAccountId: 'a1',
      );

      final afterFull = store.invoiceSummary(cardAcc.id, '2026-10')!;
      expect(afterFull.remainingCents, 0);
      expect(afterFull.isFullyPaid, true);
    });

    test('3. Smart Predictions adjustment memorizes base and deletes exhausted', () {
      final store = MoneyStore(autoBoot: false);
      store.month = '2026-10';

      store.addTransaction(
        accId: 'a1',
        date: '2026-10-01',
        payee: 'Previsão Mercado',
        catSelection: 'Alimentação › Mercado',
        memo: '',
        signedAmt: -100000, // R$ 1.000,00 ceiling
      );

      store.addTransaction(
        accId: 'a1',
        date: '2026-10-05',
        payee: 'Carrefour',
        catSelection: 'Alimentação › Mercado',
        memo: '',
        signedAmt: -35000, // R$ 350,00 spent
      );

      final res1 = store.adjustPredictions('2026-10');
      expect(res1.items.first.remainingCents, 65000);
      expect(res1.items.first.status, PredictionAdjustStatus.adjusted);

      // Re-running without new expenses must NOT double-deduct
      final res2 = store.adjustPredictions('2026-10');
      expect(res2.items.first.remainingCents, 65000);
      expect(res2.items.first.status, PredictionAdjustStatus.unchanged);

      // Spend another R$ 700,00 (exceeding the R$ 1.000,00 base) -> Prediction deleted!
      store.addTransaction(
        accId: 'a1',
        date: '2026-10-18',
        payee: 'Atacadão',
        catSelection: 'Alimentação › Mercado',
        memo: '',
        signedAmt: -70000,
      );

      final res3 = store.adjustPredictions('2026-10');
      expect(res3.hasExhausted, true);
      expect(
        store.db.txs.any((t) => isPredictionPayee(t.payee)),
        false,
      );
    });

    test('4. CashFlowEngine & QIF / CSV Importers', () {
      final store = MoneyStore(autoBoot: false);
      const qifSample = '''
!Type:Bank
D25/10/2026
T-150.75
PPadaria Real
LAlimentação:Mercado
CX
^
''';
      final summary = store.importQIFBytes(
        Uint8List.fromList(utf8.encode(qifSample)),
        targetAccountId: 'a1',
      );
      expect(summary.importedCount, 1);
      expect(store.db.txs.first.amt, -15075);

      final matrix = CashFlowEngine.buildMatrix(
        transactions: store.db.txs,
        accounts: store.db.accounts,
        periodKind: CashFlowPeriodKind.monthly,
        year: 2026,
      );
      expect(matrix.expenseSection.grandTotal, 15075);
    });
  });

  testWidgets('5. Renders OpenMoneyApp shell cleanly on Desktop & Mobile', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = MoneyStore(autoBoot: false);
    await tester.pumpWidget(OpenMoneyApp(store: store));
    await tester.pumpAndSettle();

    expect(find.text('OpenMoney'), findsWidgets);
    expect(find.text('Conta Corrente'), findsWidgets);
  });
}

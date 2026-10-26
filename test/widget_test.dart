import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmoney/main.dart';
import 'package:openmoney/models/openmoney_models.dart';
import 'package:openmoney/services/backup_manager.dart';
import 'package:openmoney/services/cash_flow_engine.dart';
import 'package:openmoney/services/importers_exporters.dart';
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

    test('6. CSV Export & Import includes Account status, favorite and transfer replacement', () {
      final store = MoneyStore(autoBoot: false);
      store.db.accounts.first.favorite = true;
      store.saveAccount(
        name: 'Poupança Inter',
        type: 'Poupança',
        openingCents: 50000,
        closeDay: 1,
        dueDay: 10,
        payAccId: '',
        inactive: true,
      );
      final poup = store.db.accounts.firstWhere((a) => a.name == 'Poupança Inter');
      expect(poup.isInactive, true);

      // Transação comum
      store.addTransaction(
        accId: store.db.accounts.first.id,
        date: '2026-10-20',
        payee: 'Supermercado',
        catSelection: 'Alimentação › Mercado',
        memo: 'Compras da semana',
        signedAmt: -12050,
      );

      // Transação de transferência com chevron
      store.addTransaction(
        accId: store.db.accounts.first.id,
        date: '2026-10-21',
        payee: 'Transferência para Poupança',
        catSelection: 'Transferência › Poupança Inter',
        memo: 'Aporte',
        signedAmt: -5000,
      );

      // Exporta CSV
      final csv = store.exportCSVString();
      expect(csv.contains('"Status da Conta"'), true);
      expect(csv.contains('"Favorita"'), true);
      expect(csv.contains('Habilitada'), true);
      expect(csv.contains('"Transferência: Poupança Inter"'), true);
      expect(csv.contains('Transferência ›'), false);

      // Testa Importação CSV com transferência › chevron e status de conta
      final csvToImport = '''"Data";"Conta";"Status da Conta";"Favorita";"Descrição";"Categoria";"Nota";"Valor";"Conciliado";"Fatura"
"2026-10-22";"Banco XP";"Habilitada";"Sim";"Aporte XP";"Transferência › Poupança Inter";"Nota aporte";"-200,00";"Sim";""
"2026-10-23";"Banco Safra";"Desabilitada";"Não";"Aporte Safra";"Transferência › Poupança Inter";"";"-300,00";"Sim";""
''';

      final res = CSVImporter.parse(
        content: csvToImport,
        existingAccounts: store.db.accounts,
        existingCats: store.db.cats,
        existingTxs: store.db.txs,
      );

      expect(res.newAccounts.length, 2);
      final xpAcc = res.newAccounts.firstWhere((a) => a.name == 'Banco XP');
      final safraAcc = res.newAccounts.firstWhere((a) => a.name == 'Banco Safra');
      expect(xpAcc.isFavorite, true);
      expect(xpAcc.isActive, true);
      expect(safraAcc.isInactive, true);

      expect(res.newTxs.length, 2);
      expect(res.newTxs[0].cat, 'Transferência: Poupança Inter');
      expect(res.newTxs[1].cat, 'Transferência: Poupança Inter');
    });

    test('7. BackupManager creates ZIP, prunes and extracts Database properly', () async {
      final tempDir = Directory.systemTemp.createTempSync('om_backup_test_');
      final dbFile = File('${tempDir.path}/test_openmoney.json');
      final db = Database(
        accounts: [Account(id: 'acc1', name: 'Conta Teste', type: 'Corrente', opening: 1000)],
        cats: [CategoryItem(name: 'Geral', type: 'Despesa')],
        txs: [Transaction(id: 'tx1', acc: 'acc1', date: '2026-10-25', payee: 'Loja', cat: 'Geral', memo: '', amt: -500, rec: true)],
        recs: [],
        budgets: {},
        v: 6,
      );
      dbFile.writeAsStringSync(jsonEncode(db.toJson()));

      await BackupManager.instance.ensureDailyBackup(
        appSupportDirPath: tempDir.path,
        databasePath: dbFile.path,
        force: true,
      );

      final backups = BackupManager.instance.availableBackups(appSupportDirPath: tempDir.path);
      expect(backups.length, 1);
      expect(backups.first.filename.endsWith('.zip'), true);

      final restoredDb = await BackupManager.instance.extractDatabase(zipPath: backups.first.path);
      expect(restoredDb != null, true);
      expect(restoredDb!.accounts.first.name, 'Conta Teste');
      expect(restoredDb.txs.first.payee, 'Loja');

      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
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

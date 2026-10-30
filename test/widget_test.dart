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
      expect(csv.contains('"Conta Ativa"'), true);
      expect(csv.contains('"Conta Favorita"'), true);
      expect(csv.contains('Sim'), true);
      expect(csv.contains('"Transferência: Poupança Inter"'), true);
      expect(csv.contains('Transferência ›'), false);

      // Valida cabeçalho exato no final
      expect(csv.contains('"Data";"Conta";"Descrição";"Categoria";"Nota";"Valor";"Conciliado";"Fatura";"Conta Favorita";"Conta Ativa"'), true);

      // Testa Importação CSV com transferência › chevron e status de conta no final
      final csvToImport = '''"Data";"Conta";"Descrição";"Categoria";"Nota";"Valor";"Conciliado";"Fatura";"Conta Favorita";"Conta Ativa"
"2026-10-22";"Banco XP";"Aporte XP";"Transferência › Poupança Inter";"Nota aporte";"-200,00";"Sim";"";"Sim";"Sim"
"2026-10-23";"Banco Safra";"Aporte Safra";"Transferência › Poupança Inter";"";"-300,00";"Sim";"";"Não";"Não"
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

    test('8. Reorder accounts within groups and persists order in JSON', () {
      final store = MoneyStore(autoBoot: false);
      store.db = Database(
        accounts: [
          Account(id: 'fav1', name: 'Fav 1', type: 'Corrente', opening: 100, favorite: true),
          Account(id: 'fav2', name: 'Fav 2', type: 'Corrente', opening: 200, favorite: true),
          Account(id: 'act1', name: 'Act 1', type: 'Corrente', opening: 300),
          Account(id: 'act2', name: 'Act 2', type: 'Corrente', opening: 400),
          Account(id: 'inact1', name: 'Inact 1', type: 'Corrente', opening: 500, inactive: true),
          Account(id: 'inact2', name: 'Inact 2', type: 'Corrente', opening: 600, inactive: true),
        ],
        cats: [],
        txs: [],
        recs: [],
        budgets: {},
        v: 6,
      );

      // Reorder favorites: move Fav 1 down
      store.moveAccountStepWithinGroup(store.favoriteAccounts, 'fav1', 1);
      expect(store.favoriteAccounts.map((a) => a.id).toList(), ['fav2', 'fav1']);

      // Reorder regular active accounts: move Act 2 up
      store.moveAccountStepWithinGroup(store.regularActiveAccounts, 'act2', -1);
      expect(store.regularActiveAccounts.map((a) => a.id).toList(), ['act2', 'act1']);

      // Reorder inactive accounts: move Inact 2 up
      store.moveAccountStepWithinGroup(store.regularInactiveAccounts, 'inact2', -1);
      expect(store.regularInactiveAccounts.map((a) => a.id).toList(), ['inact2', 'inact1']);

      // Verify JSON serialization maintains the exact new order
      final json = store.db.toJson();
      final accountsJson = (json['accounts'] as List).cast<Map<String, dynamic>>();
      expect(accountsJson.map((a) => a['id']).toList(), [
        'fav2',
        'fav1',
        'act2',
        'act1',
        'inact2',
        'inact1',
      ]);
    });

    test('9. Credit card predicted balance considers invoice date (ik) instead of transaction date', () {
      final store = MoneyStore(autoBoot: false);
      store.month = '2026-10';

      // Card with closeDay 10, dueDay 20
      store.saveAccount(
        name: 'Cartão Master',
        type: kCardType,
        openingCents: 0,
        closeDay: 10,
        dueDay: 20,
        payAccId: 'a1',
      );
      final cardAcc = store.db.accounts.firstWhere((a) => a.type == kCardType);

      // 1. Purchase on 2026-10-05 (<= closeDay 10) -> belongs to invoice 2026-10
      store.addTransaction(
        accId: cardAcc.id,
        date: '2026-10-05',
        payee: 'Mercado Outubro',
        catSelection: 'Geral',
        memo: '',
        signedAmt: -10000, // R$ 100,00
      );

      // 2. Purchase on 2026-10-15 (> closeDay 10) -> date is in Oct, but invoice is 2026-11
      store.addTransaction(
        accId: cardAcc.id,
        date: '2026-10-15',
        payee: 'Posto Novembro',
        catSelection: 'Geral',
        memo: '',
        signedAmt: -25000, // R$ 250,00
      );

      // 3. Purchase on 2026-09-20 (> closeDay 10 of Sep) -> date is in Sep, but invoice is 2026-10
      store.addTransaction(
        accId: cardAcc.id,
        date: '2026-09-20',
        payee: 'Farmácia Setembro P/ Outubro',
        catSelection: 'Geral',
        memo: '',
        signedAmt: -5000, // R$ 50,00
      );

      // Set month to 2026-10 to test prediction for October
      store.month = '2026-10';

      // In month 2026-10:
      // The predicted balance for the credit card in month 2026-10 must consider all invoices up to 2026-10:
      // - 2026-09-20 (ik: 2026-10) -> included (-5000)
      // - 2026-10-05 (ik: 2026-10) -> included (-10000)
      // - 2026-10-15 (ik: 2026-11) -> EXCLUDED from 2026-10 prediction! (it belongs to 2026-11 invoice)
      final cardBalPredOct = store.balance(cardAcc, predicted: true);
      expect(cardBalPredOct, -15000);

      // When advancing to month 2026-11:
      store.month = '2026-11';
      final cardBalPredNov = store.balance(cardAcc, predicted: true);
      expect(cardBalPredNov, -40000); // -15000 + -25000 = -40000

      // In account ledger view data: cardInvoiceMonthData for 2026-10 returns the invoice transactions (2)
      final invDataOct = store.cardInvoiceMonthData(cardAcc.id, '2026-10');
      expect(invDataOct.transactions.length, 2);
      expect(invDataOct.transactions.map((t) => t.payee).toSet(), {
        'Mercado Outubro',
        'Farmácia Setembro P/ Outubro',
      });
    });

    test('10. Credit card invoice competence named strictly by due month (dueDay <= closeDay)', () {
      final store = MoneyStore(autoBoot: false);
      store.month = '2026-11';

      // Card closing on day 23 and due on day 3 of next month
      store.saveAccount(
        name: 'Nubank Violeta',
        type: kCardType,
        openingCents: 0,
        closeDay: 23,
        dueDay: 3,
        payAccId: 'a1',
      );
      final cardAcc = store.db.accounts.firstWhere((a) => a.name == 'Nubank Violeta');
      final cardCfg = cardAcc.card!;

      // 1. Purchase on 2026-09-24 (> closeDay 23 of Sep) -> closes 23/10, due 03/11 -> Fatura 2026-11 (Novembro)
      store.addTransaction(
        accId: cardAcc.id,
        date: '2026-09-24',
        payee: 'Restaurante Fim Setembro',
        catSelection: 'Alimentação',
        memo: '',
        signedAmt: -12000,
      );

      // 2. Purchase on 2026-10-15 (<= closeDay 23 of Oct) -> closes 23/10, due 03/11 -> Fatura 2026-11 (Novembro)
      store.addTransaction(
        accId: cardAcc.id,
        date: '2026-10-15',
        payee: 'Supermercado Meio Outubro',
        catSelection: 'Alimentação',
        memo: '',
        signedAmt: -35000,
      );

      // 3. Purchase on 2026-10-24 (> closeDay 23 of Oct) -> closes 23/11, due 03/12 -> Fatura 2026-12 (Dezembro)
      store.addTransaction(
        accId: cardAcc.id,
        date: '2026-10-24',
        payee: 'Combustível Fim Outubro',
        catSelection: 'Transporte',
        memo: '',
        signedAmt: -20000,
      );

      // Check invKeyFor calculations
      expect(invKeyFor(cardCfg, '2026-09-24'), '2026-11');
      expect(invKeyFor(cardCfg, '2026-10-15'), '2026-11');
      expect(invKeyFor(cardCfg, '2026-10-24'), '2026-12');

      // Check invDates calculations for invoice 2026-11
      final datesNov = invDates(cardCfg, '2026-11');
      expect(datesNov.close, '2026-10-23');
      expect(datesNov.due, '2026-11-03');

      // Check cardInvoiceMonthData for November 2026: contains the 2 purchases closing on 23/10
      final invNov = store.cardInvoiceMonthData(cardAcc.id, '2026-11');
      expect(invNov.transactions.length, 2);
      expect(invNov.transactions.map((t) => t.payee).toSet(), {
        'Restaurante Fim Setembro',
        'Supermercado Meio Outubro',
      });

      // Invoice summary check
      final summaryNov = store.invoiceSummary(cardAcc.id, '2026-11');
      expect(summaryNov != null, true);
      expect(summaryNov!.key, '2026-11');
      expect(summaryNov.closeDate, '2026-10-23');
      expect(summaryNov.dueDate, '2026-11-03');
      expect(summaryNov.chargesCents, 47000); // 12000 + 35000

      // Auto payment transaction generated for checking account a1 on due date 2026-11-03
      final autoTx = store.db.txs.firstWhere((t) => t.auto == true && t.inv == '2026-11' && t.acc == 'a1');
      expect(autoTx.date, '2026-11-03');
      expect(autoTx.memo, 'Fatura Novembro de 2026');
      expect(autoTx.amt, -47000);

      // CSV export displays invoice as 11/2026
      final csv = store.exportCSVString(accountFilterId: cardAcc.id);
      expect(csv.contains('"11/2026"'), true);
      expect(csv.contains('"12/2026"'), true);
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

    test('11. Due bills view uses invoice due date for credit cards and only considers overdue if fatura vigente', () {
      final store = MoneyStore(autoBoot: false);
      final today = todayISO();

      // 1. Regular checking account
      store.saveAccount(
        name: 'Conta Corrente',
        type: 'Corrente',
        openingCents: 100000,
        closeDay: 1,
        dueDay: 1,
        payAccId: '',
      );
      final regularAcc = store.db.accounts.firstWhere((a) => a.type == 'Corrente');

      // 2. Credit card account (Neo - closes on 23, due on 3)
      store.saveAccount(
        name: 'Neo',
        type: kCardType,
        openingCents: 0,
        closeDay: 23,
        dueDay: 3,
        payAccId: regularAcc.id,
      );
      final cardAcc = store.db.accounts.firstWhere((a) => a.name == 'Neo');
      final cardCfg = cardAcc.card!;
      final currentIk = invKeyFor(cardCfg, today);
      final pastIk = addMonthsYM(currentIk, -2);

      // Past checking account expense (unreconciled) -> MUST be overdue
      final pastDate = addDaysDate(today, -10);
      store.db.txs.add(
        Transaction(
          id: 'tx_reg_overdue',
          acc: regularAcc.id,
          date: pastDate,
          payee: 'Conta de Energia Atrasada',
          cat: 'Moradia',
          memo: '',
          amt: -15000,
          rec: false,
        ),
      );

      // User's exact scenario: Purchase on 23/10/2026 on credit card Neo, invoice due date is next month (e.g. 03/12/2026)
      // Must NOT be considered overdue because the invoice due date is far in the future
      store.db.txs.add(
        Transaction(
          id: 'tx_card_neo_future_due',
          acc: cardAcc.id,
          date: addDaysDate(today, -4),
          payee: 'Compra Recente Neo',
          cat: 'Geral',
          memo: '',
          amt: -5000,
          rec: false,
          ik: currentIk,
        ),
      );

      // Past credit card expense from an OLD invoice whose invoice due date was in the past -> MUST NOT be considered overdue
      store.db.txs.add(
        Transaction(
          id: 'tx_card_old_inv',
          acc: cardAcc.id,
          date: addDaysDate(today, -60),
          payee: 'Compra Fatura Antiga',
          cat: 'Geral',
          memo: '',
          amt: -8000,
          rec: false,
          ik: pastIk,
        ),
      );

      // A credit card transaction in the current invoice with custom invoice info where invoice due date passed
      cardAcc.invoices ??= {};
      final overdueIk = '2026-overdue-test';
      cardAcc.invoices![overdueIk] = InvoiceInfo(
        close: addDaysDate(today, -15),
        due: addDaysDate(today, -5),
        pay: regularAcc.id,
      );

      final items = store.dueBillItems(withinDays: 3);
      final itemIds = items.map((i) => i.tx.id).toSet();

      // The regular account overdue bill MUST be present
      expect(itemIds.contains('tx_reg_overdue'), true);

      // The user's credit card transaction (whose invoice due date is in the future) MUST NOT be in the due bills list
      expect(itemIds.contains('tx_card_neo_future_due'), false);

      // The credit card transaction from an OLD invoice MUST NOT be considered overdue
      expect(itemIds.contains('tx_card_old_inv'), false);

      final summary = store.dueBillsSummary(withinDays: 3);
      expect(summary.overdueCount, 1);
    });

    test('16. CSV Import of Credit Card transactions creates reconciled invoice payment in default payment account on due date', () {
      final store = MoneyStore(autoBoot: false);
      store.db = Database(
        accounts: [],
        cats: List<CategoryItem>.from(kDefaultCats),
        txs: [],
        recs: [],
        budgets: {},
      );

      // 1. Conta padrão Y para débito (Conta Corrente Y)
      store.saveAccount(
        name: 'Conta Padrão Y',
        type: 'Corrente',
        openingCents: 1000000, // R$ 10.000,00
        closeDay: 1,
        dueDay: 1,
        payAccId: '',
      );
      final accY = store.db.accounts.firstWhere((a) => a.name == 'Conta Padrão Y');

      // 2. Cartão de crédito X com vencimento no dia 05 e conta padrão Y
      store.saveAccount(
        name: 'Cartão X',
        type: kCardType,
        openingCents: 0,
        closeDay: 28,
        dueDay: 5,
        payAccId: accY.id,
      );
      final cardX = store.db.accounts.firstWhere((a) => a.name == 'Cartão X');

      // 3. Importa CSV com R$ 2.000,00 na fatura de janeiro/2026 e R$ 2.000,00 na fatura de novembro/2026
      const csvContent = '''
"Data";"Conta";"Descrição";"Categoria";"Nota";"Valor";"Conciliado";"Fatura"
"2025-12-15";"Cartão X";"Compra A";"Alimentação";"";"-1200,00";"Sim";"01/2026"
"2025-12-20";"Cartão X";"Compra B";"Lazer";"";"-800,00";"Sim";"01/2026"
"2026-10-18";"Cartão X";"Compra C";"Moradia";"";"-2000,00";"Sim";"11/2026"
''';
      final bytes = Uint8List.fromList(utf8.encode(csvContent));
      final importRes = store.importCSVBytes(bytes);
      expect(importRes.importedCount, 3);

      // Verifica pagamento conciliado na Conta Padrão Y para a fatura passada 01/2026 no dia 05/01/2026 (<= hoje)
      final payJan = store.db.txs.firstWhere(
        (t) => t.acc == accY.id && t.inv == '2026-01' && t.card == cardX.id,
      );
      expect(payJan.date, '2026-01-05');
      expect(payJan.amt, -200000); // -R$ 2.000,00
      expect(payJan.rec, true);
      expect(payJan.auto, isNull);

      // Verifica que para a fatura futura 11/2026 (vencimento 05/11/2026 > hoje),
      // o lançamento de pagamento na Conta Padrão Y NÃO fica conciliado (rec: false)
      final payNov = store.db.txs.firstWhere(
        (t) => t.acc == accY.id && t.inv == '2026-11' && t.card == cardX.id,
      );
      expect(payNov.date, '2026-11-05');
      expect(payNov.amt, -200000); // -R$ 2.000,00
      expect(payNov.rec, false);

      // Verifica fatura 01/2026 liquidada no Cartão X
      final summaryJan = store.invoiceSummary(cardX.id, '2026-01')!;
      expect(summaryJan.chargesCents, 200000);
      expect(summaryJan.paymentsCents, 200000);
      expect(summaryJan.remainingCents, 0);
      expect(summaryJan.isFullyPaid, true);

      // Verifica fatura futura 11/2026 ainda em aberto (não liquidada antes do vencimento)
      final summaryNov = store.invoiceSummary(cardX.id, '2026-11')!;
      expect(summaryNov.chargesCents, 200000);
      expect(summaryNov.paymentsCents, 0);
      expect(summaryNov.remainingCents, 200000);
      expect(summaryNov.isFullyPaid, false);

      // Saldo conciliado da Conta Padrão Y desconta apenas a fatura vencida (01/2026):
      // R$ 10.000,00 - R$ 2.000,00 = R$ 8.000,00
      expect(store.balance(accY, predicted: false), 800000);
    });

    test('17. TransactionCopy preserves source tx and supports installment & card invoice calculation', () {
      final store = MoneyStore(autoBoot: false);
      store.saveAccount(
        name: 'Conta Corrente',
        type: 'Corrente',
        openingCents: 100000,
        closeDay: 1,
        dueDay: 1,
        payAccId: '',
      );
      final currentAcc = store.db.accounts.first;

      store.saveAccount(
        name: 'Cartão Black',
        type: kCardType,
        openingCents: 0,
        closeDay: 10,
        dueDay: 20,
        payAccId: currentAcc.id,
      );
      final cardAcc = store.db.accounts.firstWhere((a) => a.type == kCardType);

      // Cria transação parcelada original no cartão
      store.addTransaction(
        accId: cardAcc.id,
        date: '2026-10-15',
        payee: 'Notebook Gamer',
        catSelection: 'Compras',
        memo: 'Parcela de teste',
        signedAmt: -300000,
        mode: 'installment',
        installments: 3,
      );

      final manualInstallments = store.db.txs.where((t) => t.plan != null && t.payee.startsWith('Notebook Gamer')).toList();
      expect(manualInstallments.length, 3);
      final firstInstallment = manualInstallments.firstWhere((t) => t.pn == 1);
      expect(firstInstallment.pt, 3);
      expect(firstInstallment.payee, 'Notebook Gamer (1/3)');

      // Simula a lógica de cópia do TransactionCopySheet
      final cleanPayee = firstInstallment.payee.replaceAll(RegExp(r'\s*\(\d+\/\d+\)$'), '').trim();
      expect(cleanPayee, 'Notebook Gamer');

      // Copia para conta corrente como lançamento único independente
      store.addTransaction(
        accId: currentAcc.id,
        date: '2026-10-27',
        payee: cleanPayee,
        catSelection: firstInstallment.cat,
        memo: firstInstallment.memo,
        signedAmt: -firstInstallment.amt.abs(),
        mode: 'single',
      );

      final copiedTx = store.db.txs.last;
      expect(copiedTx.payee, 'Notebook Gamer');
      expect(copiedTx.acc, currentAcc.id);
      expect(copiedTx.plan, isNull);
      expect(copiedTx.pn, isNull);
      expect(copiedTx.pt, isNull);
      expect(copiedTx.amt, -100000); // 100000 cents preservado do primeiro lançamento
      // Garante que o lançamento original não foi modificado
      expect(firstInstallment.payee, 'Notebook Gamer (1/3)');
      expect(firstInstallment.acc, cardAcc.id);
    });

    test('18. Multi-account filter and Business entity (PF / PJ) cash flow & report reconciliation rules', () {
      final store = MoneyStore(autoBoot: false);
      store.db.accounts.clear();
      store.db.txs.clear();

      // 1. Cadastra contas PF e PJ com o campo business
      store.saveAccount(
        name: 'Nubank PF',
        type: 'Corrente',
        openingCents: 100000, // R$ 1.000,00
        closeDay: 1,
        dueDay: 10,
        payAccId: '',
        business: 'PF',
      );
      final accPf1 = store.db.accounts.first;

      store.saveAccount(
        name: 'Cartão UV PF',
        type: kCardType,
        openingCents: 0,
        closeDay: 10,
        dueDay: 20,
        payAccId: accPf1.id,
        business: 'PF',
      );
      final cardPf = store.db.accounts.firstWhere((a) => a.type == kCardType);

      store.saveAccount(
        name: 'Inter PJ',
        type: 'Corrente',
        openingCents: 500000, // R$ 5.000,00
        closeDay: 1,
        dueDay: 10,
        payAccId: '',
        business: 'PJ',
      );
      final accPj = store.db.accounts.firstWhere((a) => a.name == 'Inter PJ');

      // Verifica agrupamento de negócios no store
      expect(store.allBusinesses, containsAll(['PF', 'PJ']));
      final pfAccounts = store.accountsForBusiness('PF');
      expect(pfAccounts.length, 2);
      expect(pfAccounts.map((a) => a.name), containsAll(['Nubank PF', 'Cartão UV PF']));

      // 2. Transações
      // Tx1: Receita direta em PF (Salário R$ 300,00)
      store.addTransaction(
        accId: accPf1.id,
        date: '2026-05-10',
        payee: 'Salário',
        catSelection: 'Rendimento : Salário',
        memo: '',
        signedAmt: 30000,
        mode: 'single',
      );

      // Tx2: Despesa em PF no cartão (Supermercado R$ 100,00)
      store.addTransaction(
        accId: cardPf.id,
        date: '2026-05-12',
        payee: 'Mercado',
        catSelection: 'Alimentação : Supermercado',
        memo: '',
        signedAmt: -10000,
        mode: 'single',
      );

      // Tx3: Transferência INTERNA dentro de PF (Conta Nubank -> Pagamento Fatura Cartão UV R$ 100,00)
      store.addTransaction(
        accId: accPf1.id,
        date: '2026-05-20',
        payee: 'Pagamento Cartão',
        catSelection: 'xfer:${cardPf.id}',
        memo: '',
        signedAmt: -10000,
        mode: 'single',
      );

      // Tx4: Transferência ENTRE NEGÓCIOS (PJ -> PF Distribuição de Lucro R$ 2.000,00)
      store.addTransaction(
        accId: accPj.id,
        date: '2026-05-05',
        payee: 'Distribuição de Lucros',
        catSelection: 'xfer:${accPf1.id}',
        memo: '',
        signedAmt: -200000,
        mode: 'single',
      );

      // 3. Teste do Fluxo de Caixa filtrando apenas PF (Nubank PF + Cartão UV)
      final pfIds = {accPf1.id, cardPf.id};
      final matrixPf = CashFlowEngine.buildMatrix(
        transactions: store.db.txs,
        accounts: store.db.accounts,
        periodKind: CashFlowPeriodKind.monthly,
        year: 2026,
        accountFilterIds: pfIds,
      );

      // Na matriz de PF:
      // - Tx3 (transferência interna entre Nubank e Cartão UV) DEVE SER IGNORADA
      // - Tx4 (transferência vinda da PJ para a PF) DEVE APARECER como Receita/Entrada de R$ 2.000,00
      final mayColIndex = 4; // Maio (mês 5, índice 4)
      final totalIncomeMay = matrixPf.incomeSection.periodTotals[mayColIndex];
      // Rendimento = R$ 300,00 (Salário) + R$ 2.000,00 (Entrada externa vinda da PJ) = R$ 2.300,00 (230000 cents)
      expect(totalIncomeMay, 230000);

      final totalExpenseMay = matrixPf.expenseSection.periodTotals[mayColIndex];
      // Despesa = R$ 100,00 (Mercado) - a transferência interna não soma despesa
      expect(totalExpenseMay, 10000);

      // Saldo inicial do grupo PF: apenas abertura de accPf1 (100000), cartão é 0
      expect(matrixPf.priorBalancePeriodTotals[0], 100000);

      // 4. Teste do Fluxo de Caixa filtrando apenas PJ (Inter PJ)
      final pjIds = {accPj.id};
      final matrixPj = CashFlowEngine.buildMatrix(
        transactions: store.db.txs,
        accounts: store.db.accounts,
        periodKind: CashFlowPeriodKind.monthly,
        year: 2026,
        accountFilterIds: pjIds,
      );

      // Na matriz de PJ:
      // - Tx4 (saída de R$ 2.000,00 para PF) DEVE APARECER como Despesa/Saída
      final totalExpenseMayPj = matrixPj.expenseSection.periodTotals[mayColIndex];
      expect(totalExpenseMayPj, 200000);
      expect(matrixPj.priorBalancePeriodTotals[0], 500000); // Saldo inicial PJ = 500000

      // 5. Teste em "Todas as Contas" (sem filtro)
      final matrixAll = CashFlowEngine.buildMatrix(
        transactions: store.db.txs,
        accounts: store.db.accounts,
        periodKind: CashFlowPeriodKind.monthly,
        year: 2026,
        accountFilterIds: null,
      );
      // Todas as transferências (internas ao sistema como um todo) são ignoradas
      expect(matrixAll.incomeSection.periodTotals[mayColIndex], 30000); // Apenas Salário R$ 300,00
      expect(matrixAll.expenseSection.periodTotals[mayColIndex], 10000); // Apenas Mercado R$ 100,00

      // 6. Teste de Relatório Mensal filtrando por conta
      final reportPf = store.buildMonthlyReport('2026-05', accountFilterIds: pfIds);
      expect(reportPf.totalIncome, 30000); // Relatório ignora xfer/peer e inclui apenas receitas categorizadas
      expect(reportPf.totalExpense, 10000);
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

  test('19. Font scale and Accessibility zoom controls operate correctly', () {
    final store = MoneyStore(autoBoot: false);
    expect(store.fontScale, 1.0);
    expect(store.fontScaleLabel, '100% (Padrão)');

    store.zoomIn();
    expect(store.fontScale, 1.15);
    expect(store.fontScaleLabel, '115%');

    store.zoomIn();
    expect(store.fontScale, 1.30);
    expect(store.fontScaleLabel, '130%');

    store.zoomIn();
    expect(store.fontScale, 1.45);
    expect(store.fontScaleLabel, '145%');

    // Should not exceed maximum
    store.zoomIn();
    expect(store.fontScale, 1.45);

    store.zoomOut();
    expect(store.fontScale, 1.30);

    store.resetZoom();
    expect(store.fontScale, 1.0);
    expect(store.fontScaleLabel, '100% (Padrão)');

    store.zoomOut();
    expect(store.fontScale, 0.90);
    expect(store.fontScaleLabel, '90%');

    // Should not go below minimum
    store.zoomOut();
    expect(store.fontScale, 0.90);

    store.resetZoom();
    expect(store.fontScale, 1.0);
  });

  test('20. Category import hierarchical creation and slash/separator handling', () {
    final existingCats = [
      CategoryItem(name: 'Transporte', parent: null, type: 'Despesa'),
      CategoryItem(name: 'Automóvel', parent: 'Transporte', type: 'Despesa'),
    ];

    // CSV line with "Compra / Automóvel" or "Compra > Automóvel"
    const csvContent = '''
Data;Conta;Descrição;Categoria;Nota;Valor;Conciliado
2026-10-15;Carteira;Posto;Compra / Automóvel;;-150,00;Sim
2026-10-16;Carteira;Padaria;Alimentação > Lanche;;-25,00;Sim
''';

    final result = CSVImporter.parse(
      content: csvContent,
      existingAccounts: [Account(id: 'acc1', name: 'Carteira', type: 'Dinheiro', opening: 0)],
      existingCats: existingCats,
      existingTxs: [],
    );

    // Should create Compra as parent and Automóvel under Compra
    expect(result.newCats.any((c) => c.name == 'Compra' && c.parent == null), isTrue);
    expect(result.newCats.any((c) => c.name == 'Automóvel' && c.parent == 'Compra'), isTrue);

    // Should create Alimentação as parent and Lanche under Alimentação
    expect(result.newCats.any((c) => c.name == 'Alimentação' && c.parent == null), isTrue);
    expect(result.newCats.any((c) => c.name == 'Lanche' && c.parent == 'Alimentação'), isTrue);

    // Verify imported transactions have normalized path
    expect(result.newTxs[0].cat, 'Compra › Automóvel');
    expect(result.newTxs[1].cat, 'Alimentação › Lanche');
  });
}

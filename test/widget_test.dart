import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmoney/main.dart';
import 'package:openmoney/models/openmoney_models.dart';
import 'package:openmoney/services/audit_log_manager.dart';
import 'package:openmoney/services/backup_manager.dart';
import 'package:openmoney/services/cash_flow_engine.dart';
import 'package:openmoney/services/importers_exporters.dart';
import 'package:openmoney/store/money_store.dart';
import 'package:openmoney/ui/views/account_ledger_view.dart';
import 'package:openmoney/ui/views/budget_view.dart';
import 'package:openmoney/ui/views/categories_view.dart';
import 'package:openmoney/ui/views/cash_flow_view.dart';
import 'package:openmoney/ui/views/due_bills_view.dart';
import 'package:openmoney/ui/views/installments_view.dart';
import 'package:openmoney/ui/views/reports_view.dart';
import 'package:openmoney/ui/views/settings_view.dart';
import 'package:openmoney/ui/modals/account_multi_select_filter.dart';
import 'package:openmoney/ui/modals/account_modal.dart';
import 'package:openmoney/ui/modals/batch_edit_transactions_modal.dart';
import 'package:openmoney/ui/modals/csv_qif_modal.dart';
import 'package:openmoney/ui/modals/transaction_modal.dart';

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
      final predTx = store.db.txs.firstWhere((t) => isPredictionPayee(t.payee));
      expect(predTx.amt, 0);
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

      // 3. Importa CSV com R$ 2.000,00 na fatura de janeiro/2026 e R$ 2.000,00 na fatura de dezembro/2026 (futura)
      const csvContent = '''
"Data";"Conta";"Descrição";"Categoria";"Nota";"Valor";"Conciliado";"Fatura"
"2025-12-15";"Cartão X";"Compra A";"Alimentação";"";"-1200,00";"Sim";"01/2026"
"2025-12-20";"Cartão X";"Compra B";"Lazer";"";"-800,00";"Sim";"01/2026"
"2026-11-18";"Cartão X";"Compra C";"Moradia";"";"-2000,00";"Sim";"12/2026"
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
      expect(payJan.auto, true);

      // Verifica que para a fatura futura 12/2026 (vencimento 05/12/2026 > hoje),
      // o lançamento de pagamento na Conta Padrão Y NÃO fica conciliado (rec: false)
      final payDec = store.db.txs.firstWhere(
        (t) => t.acc == accY.id && t.inv == '2026-12' && t.card == cardX.id,
      );
      expect(payDec.date, '2026-12-05');
      expect(payDec.amt, -200000); // -R$ 2.000,00
      expect(payDec.rec, false);

      // Verifica fatura 01/2026 liquidada no Cartão X
      final summaryJan = store.invoiceSummary(cardX.id, '2026-01')!;
      expect(summaryJan.chargesCents, 200000);
      expect(summaryJan.paymentsCents, 200000);
      expect(summaryJan.remainingCents, 0);
      expect(summaryJan.isFullyPaid, true);

      // Verifica fatura futura 12/2026 ainda em aberto (não liquidada antes do vencimento)
      final summaryDec = store.invoiceSummary(cardX.id, '2026-12')!;
      expect(summaryDec.chargesCents, 200000);
      expect(summaryDec.paymentsCents, 0);
      expect(summaryDec.remainingCents, 200000);
      expect(summaryDec.isFullyPaid, false);

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

    // Test separation of mobile vs desktop fontScale
    store.fontScaleDesktop = 1.0;
    store.fontScaleMobile = 1.15;
    expect(store.fontScaleDesktop, 1.0);
    expect(store.fontScaleMobile, 1.15);

    // exportPreferencesMap must NOT contain fontScale (cloud sync isolation)
    final prefs = store.exportPreferencesMap();
    expect(prefs.containsKey('fontScale'), isFalse);
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

  test('21. Navigating to accounts adjusts month: open invoice for credit cards, current month for non-cards', () {
    final store = MoneyStore(autoBoot: false);
    store.saveAccount(
      name: 'Cartão Master',
      type: kCardType,
      openingCents: 0,
      closeDay: 1,
      dueDay: 10,
      payAccId: 'a1',
    );
    final card = store.db.accounts.firstWhere((a) => a.type == kCardType);
    final checking = store.db.accounts.firstWhere((a) => a.type != kCardType);

    // Set month to a past closed invoice/month
    store.month = '2020-01';

    // Navigate to card account -> advances to open invoice
    store.navigateTo(NavModule.account, accountId: card.id);
    final expectedOpenIk = invKeyFor(card.card!, todayISO());
    expect(store.month, expectedOpenIk);

    // Set month to a past month
    store.month = '2020-05';

    // Navigate to non-card checking account -> resets to current calendar month
    store.navigateTo(NavModule.account, accountId: checking.id);
    expect(store.month, todayISO().substring(0, 7));
  });

  test('22. Blocked category is excluded from selection options and paths but remains in reports/db', () {
    final store = MoneyStore(autoBoot: false);

    // Save a new active category and a subcategory
    store.saveCategory(name: 'Projetos', type: 'Despesa');
    store.saveCategory(name: 'Beta', parent: 'Projetos', type: 'Despesa');

    expect(store.allCategoryPaths('Despesa').contains('Projetos'), isTrue);
    expect(store.allCategoryPaths('Despesa').contains('Projetos › Beta'), isTrue);

    // Block the subcategory
    store.toggleCategoryBlocked('Projetos › Beta');
    expect(store.isCategoryBlocked('Projetos › Beta'), isTrue);
    expect(store.allCategoryPaths('Despesa').contains('Projetos › Beta'), isFalse);
    expect(store.allCategoryPaths('Despesa', includeBlocked: true).contains('Projetos › Beta'), isTrue);

    // Block the parent category
    store.toggleCategoryBlocked('Projetos');
    expect(store.isCategoryBlocked('Projetos'), isTrue);
    expect(store.allCategoryPaths('Despesa').contains('Projetos'), isFalse);
    expect(store.allCategoryPaths('Despesa', includeBlocked: true).contains('Projetos'), isTrue);

    // Serializes and round-trips correctly with blocked attribute
    final json = store.db.toJson();
    final reloadedDb = Database.fromJson(json);
    final reloadedProjetos = reloadedDb.cats.firstWhere((c) => c.path == 'Projetos');
    final reloadedBeta = reloadedDb.cats.firstWhere((c) => c.path == 'Projetos › Beta');
    expect(reloadedProjetos.isBlocked, isTrue);
    expect(reloadedBeta.isBlocked, isTrue);

    // Unblock via saveCategory editing with blocked: false (verifies fix where editing unblocks category and propagates to subcategories)
    store.saveCategory(
      editingPath: 'Projetos',
      name: 'Projetos',
      type: 'Despesa',
      blocked: false,
    );
    expect(store.isCategoryBlocked('Projetos'), isFalse);
    expect(store.isCategoryBlocked('Projetos › Beta'), isFalse);
    expect(store.allCategoryPaths('Despesa').contains('Projetos'), isTrue);
    expect(store.allCategoryPaths('Despesa').contains('Projetos › Beta'), isTrue);
  });

  test('23. Inserting a credit card transaction sets store.month to invoice key (ik) instead of transaction date', () {
    final store = MoneyStore(autoBoot: false);
    store.saveAccount(
      name: 'Nubank Card',
      type: kCardType,
      openingCents: 0,
      closeDay: 25,
      dueDay: 5, // dueDay <= closeDay -> closeDay 25/10 closes invoice for 11; after 25/10 it falls in 12
      payAccId: 'a1',
    );
    final card = store.db.accounts.firstWhere((a) => a.type == kCardType);

    // Initial month is some old month
    store.month = '2026-01';

    // Purchase made on 2026-10-26 (after closeDay 25) -> falls into invoice 2026-12!
    store.addTransaction(
      accId: card.id,
      date: '2026-10-26',
      payee: 'Restaurante',
      catSelection: 'Alimentação › Restaurantes',
      memo: '',
      signedAmt: -10000,
    );

    // Should direct to invoice month (2026-12), not date month (2026-10)
    expect(store.month, '2026-12');

    // For a normal checking account, it directs to the transaction date's month
    final checking = store.db.accounts.firstWhere((a) => a.type != kCardType);
    store.addTransaction(
      accId: checking.id,
      date: '2026-10-26',
      payee: 'Mercado',
      catSelection: 'Alimentação › Mercado',
      memo: '',
      signedAmt: -5000,
    );
    expect(store.month, '2026-10');
  });

  testWidgets('24. CashFlowView: Export CSV compact button, equal filter box heights, and KPI summary cards parity', (tester) async {
    final store = MoneyStore(autoBoot: false);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 900,
            child: CashFlowView(store: store),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Export CSV compact button with tooltip
    final exportFinder = find.byTooltip('Exportar CSV');
    expect(exportFinder, findsOneWidget);
    final exportBtn = tester.widget<OutlinedButton>(
      find.descendant(of: exportFinder, matching: find.byType(OutlinedButton)),
    );
    expect(exportBtn, isNotNull);
    expect(find.descendant(of: exportFinder, matching: find.byIcon(Icons.download)), findsOneWidget);

    // 2. Filter bar box heights equality (category search matches dropdowns)
    final categoryFieldFinder = find.widgetWithText(TextField, 'Filtrar categoria...');
    expect(categoryFieldFinder, findsOneWidget);
    final statusFieldFinder = find.byType(DropdownButtonFormField<CashFlowStatusFilter>);
    expect(statusFieldFinder, findsOneWidget);

    final hCategory = tester.getSize(categoryFieldFinder).height;
    final hStatus = tester.getSize(statusFieldFinder).height;
    expect(hCategory, equals(40.0));
    expect(hStatus, equals(40.0));
    expect(hCategory, equals(hStatus));

    // 3. KPI Summary cards (Receitas, Despesas, Resultado Líquido)
    expect(find.text('TOTAL RECEITAS'), findsOneWidget);
    expect(find.text('TOTAL DESPESAS'), findsOneWidget);
    expect(find.text('RESULTADO LÍQUIDO'), findsOneWidget);
    expect(find.byIcon(Icons.north_east), findsOneWidget);
    expect(find.byIcon(Icons.south_east), findsOneWidget);
    expect(
      find.byIcon(Icons.check_circle_rounded),
      findsWidgets, // May be in result card or header
    );
  });

  testWidgets('25. Compact icon-only export/import buttons in AccountLedger, Reports, and Categories', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = MoneyStore(autoBoot: false);

    // 1. AccountLedgerView
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountLedgerView(store: store, account: store.activeAccounts.first),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final ledgerCsvTooltip = find.byTooltip('Exportar CSV');
    expect(ledgerCsvTooltip, findsOneWidget);
    expect(find.descendant(of: ledgerCsvTooltip, matching: find.byType(OutlinedButton)), findsOneWidget);
    expect(find.descendant(of: ledgerCsvTooltip, matching: find.byIcon(Icons.download)), findsOneWidget);

    final ledgerPdfTooltip = find.byTooltip('Exportar Extrato PDF');
    expect(ledgerPdfTooltip, findsOneWidget);
    expect(find.descendant(of: ledgerPdfTooltip, matching: find.byType(OutlinedButton)), findsOneWidget);
    expect(find.descendant(of: ledgerPdfTooltip, matching: find.byIcon(Icons.picture_as_pdf)), findsOneWidget);

    // 2. ReportsView
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportsView(store: store),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final reportsPdfTooltip = find.byTooltip('Exportar PDF A4');
    expect(reportsPdfTooltip, findsOneWidget);
    expect(find.descendant(of: reportsPdfTooltip, matching: find.byType(OutlinedButton)), findsOneWidget);
    expect(find.descendant(of: reportsPdfTooltip, matching: find.byIcon(Icons.picture_as_pdf)), findsOneWidget);

    // 3. CategoriesView
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CategoriesView(store: store),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final catImportTooltip = find.byTooltip('Importar CSV');
    expect(catImportTooltip, findsOneWidget);
    expect(find.descendant(of: catImportTooltip, matching: find.byType(OutlinedButton)), findsOneWidget);
    expect(find.descendant(of: catImportTooltip, matching: find.byIcon(Icons.file_upload_outlined)), findsOneWidget);

    final catExportTooltip = find.byTooltip('Exportar CSV');
    expect(catExportTooltip, findsOneWidget);
    expect(find.descendant(of: catExportTooltip, matching: find.byType(OutlinedButton)), findsOneWidget);
    expect(find.descendant(of: catExportTooltip, matching: find.byIcon(Icons.download)), findsOneWidget);
  });

  testWidgets('26. DueBillsView & InstallmentsView compact CSV button, and CashFlowView filter alignment', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = MoneyStore(autoBoot: false);

    // 1. DueBillsView
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DueBillsView(store: store),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dueBillsCsvTooltip = find.byTooltip('Exportar CSV');
    expect(dueBillsCsvTooltip, findsOneWidget);
    expect(find.descendant(of: dueBillsCsvTooltip, matching: find.byType(OutlinedButton)), findsOneWidget);
    expect(find.descendant(of: dueBillsCsvTooltip, matching: find.byIcon(Icons.download)), findsOneWidget);

    // 2. InstallmentsView
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InstallmentsView(store: store),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final installmentsCsvTooltip = find.byTooltip('Exportar CSV');
    expect(installmentsCsvTooltip, findsOneWidget);
    expect(find.descendant(of: installmentsCsvTooltip, matching: find.byType(OutlinedButton)), findsOneWidget);
    expect(find.descendant(of: installmentsCsvTooltip, matching: find.byIcon(Icons.download)), findsOneWidget);

    // 3. CashFlowView filter alignment: Contas filter top matches Status and other dropdowns
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CashFlowView(store: store),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final accRect = tester.getRect(find.byType(AccountMultiSelectFilter));
    final statusRect = tester.getRect(find.ancestor(
      of: find.byType(DropdownButtonFormField<CashFlowStatusFilter>),
      matching: find.byType(SizedBox),
    ).first);

    expect(accRect.top, equals(statusRect.top));
    expect(accRect.height, equals(40.0));
    expect(statusRect.height, equals(40.0));
  });

  testWidgets('27. Database button and modal renamed strictly to "Base de Dados Local"', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = MoneyStore(autoBoot: false);
    await tester.pumpWidget(OpenMoneyApp(store: store));
    await tester.pumpAndSettle();

    // Verify button tooltip is 'Base de Dados Local'
    final dbBtn = find.byTooltip('Base de Dados Local');
    expect(dbBtn, findsWidgets);

    // Tap the first database button to open modal
    await tester.tap(dbBtn.first);
    await tester.pumpAndSettle();

    // Verify modal title is 'Base de Dados Local'
    expect(find.text('Base de Dados Local'), findsWidgets);
    expect(find.text('Abrir Base Existente'), findsOneWidget);
    expect(find.text('Criar Nova Base'), findsOneWidget);
    expect(find.text('Arquivos Recentes'), findsOneWidget);
    expect(find.text('Fechar'), findsOneWidget);
  });

  testWidgets('28. Local database footer is single line and recent files persist cleanly', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = MoneyStore(autoBoot: false);

    await tester.pumpWidget(OpenMoneyApp(store: store));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Base de Dados Local'), findsWidgets);

    // Verify footer single-line text and version
    final footerText = find.textContaining('Base Local • v');
    expect(footerText, findsOneWidget);
    final textWidget = tester.widget<Text>(footerText);
    expect(textWidget.maxLines, equals(1));
    expect(textWidget.softWrap, isFalse);
  });

  testWidgets('29. Cash flow ending balance comments support add, edit, delete, persistence and indicators', (tester) async {
    tester.view.physicalSize = const Size(2400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = MoneyStore(autoBoot: false);

    // 1. Verify model serialization / deserialization
    store.setCommentForPeriod('2026-10', 'Reserva de emergência aplicada');
    expect(store.commentForPeriod('2026-10'), equals('Reserva de emergência aplicada'));

    final json = store.db.toJson();
    expect(json['comments'], isA<Map>());
    expect((json['comments'] as Map)['2026-10'], equals('Reserva de emergência aplicada'));

    final reloadedDb = Database.fromJson(json);
    expect(reloadedDb.comments['2026-10'], equals('Reserva de emergência aplicada'));

    // 2. Open Cash Flow view
    store.activeModule = NavModule.cashFlow;
    await tester.pumpWidget(OpenMoneyApp(store: store));
    await tester.pumpAndSettle();

    // Verify Ending balance row
    expect(find.text('Saldo Final Acumulado'), findsOneWidget);

    // Verify comment icon indicator exists
    expect(find.byIcon(Icons.comment_outlined), findsWidgets);

    // Verify cell tooltip containing the comment
    expect(
      find.byTooltip('Comentário (10/2026):\nReserva de emergência aplicada\n(Clique para editar)'),
      findsOneWidget,
    );

    // 3. Tap on the cell to open comment dialog
    await tester.tap(find.byTooltip('Comentário (10/2026):\nReserva de emergência aplicada\n(Clique para editar)'));
    await tester.pumpAndSettle();

    expect(find.text('Comentário do Saldo Final'), findsOneWidget);
    expect(find.text('Excluir'), findsOneWidget);

    // Edit text and save
    await tester.enterText(find.byType(TextField).last, 'Novo comentário revisado');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(store.commentForPeriod('2026-10'), equals('Novo comentário revisado'));

    // 4. Tap again and delete
    await tester.tap(find.byTooltip('Comentário (10/2026):\nNovo comentário revisado\n(Clique para editar)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();

    expect(store.commentForPeriod('2026-10'), isNull);
  });

  testWidgets('30. CashFlowView: 12 months plus Total fit in 1920x1080 resolution without horizontal clipping', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = MoneyStore(autoBoot: false);
    store.activeModule = NavModule.cashFlow;

    await tester.pumpWidget(OpenMoneyApp(store: store));
    await tester.pumpAndSettle();

    // Verify first and last month headers are rendered within screen bounds
    final firstMonthFinder = find.text('JAN');
    final lastMonthFinder = find.text('DEZ');
    final totalHeaderFinder = find.text('Total');

    expect(firstMonthFinder, findsOneWidget);
    expect(lastMonthFinder, findsOneWidget);
    expect(totalHeaderFinder, findsWidgets);

    // Verify last column (Total) is on screen and not clipped outside bounds
    final lastMonthRect = tester.getRect(lastMonthFinder);
    expect(lastMonthRect.right, lessThanOrEqualTo(1920.0));
  });

  test('31. BackupManager supports local daily & manual backups for Cloud mode databases', () async {
    final tempDir = Directory.systemTemp.createTempSync('om_cloud_backup_test_');
    final db = Database(
      accounts: [Account(id: 'a1', name: 'Nuvem CC', type: 'Corrente', opening: 5000)],
      cats: [CategoryItem(name: 'Alimentação', type: 'Despesa')],
      txs: [Transaction(id: 't1', acc: 'a1', date: '2026-11-08', payee: 'Mercado', cat: 'Alimentação', memo: '', amt: -1500, rec: true)],
      recs: [],
      budgets: {},
      v: 7,
    );
    final jsonStr = jsonEncode(db.toJson());

    // 1. Manual backup from Cloud database
    final manualPath = await BackupManager.instance.createTimestampedBackup(
      appSupportDirPath: tempDir.path,
      databasePath: 'cloud://usuario@email.com',
      jsonContent: jsonStr,
      prefix: 'manual',
    );
    expect(manualPath != null, true);
    expect(File(manualPath!).existsSync(), true);
    expect(manualPath.contains('openmoney-cloud-usuario_email.com-manual'), true);

    // 2. Daily backup from Cloud database
    await BackupManager.instance.ensureDailyBackup(
      appSupportDirPath: tempDir.path,
      databasePath: 'cloud://usuario@email.com',
      jsonContent: jsonStr,
      force: true,
    );

    final backups = BackupManager.instance.availableBackups(appSupportDirPath: tempDir.path);
    expect(backups.length >= 2, true);

    // 3. Extract and restore
    final restored = await BackupManager.instance.extractDatabase(zipPath: manualPath);
    expect(restored != null, true);
    expect(restored!.accounts.first.name, 'Nuvem CC');
    expect(restored.txs.first.payee, 'Mercado');
    expect(restored.txs.first.amt, -1500);

    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('32. AuditLogManager handles Cloud mode databases and local/remote audit persistence', () async {
    final tempDir = Directory.systemTemp.createTempSync('om_audit_test_');
    AuditLogManager.instance.defaultAppSupportDirPath = tempDir.path;

    // 1. Path resolution for cloud mode
    final logPath = AuditLogManager.instance.logFilePathForDatabase(
      'cloud://fabiano@teste.com',
      appSupportDirPath: tempDir.path,
    );
    expect(logPath.contains('openmoney-cloud-fabiano_teste.com.log'), true);

    // 2. Logging in cloud mode
    AuditLogManager.instance.logAsync(
      dbPath: 'cloud://fabiano@teste.com',
      appSupportDirPath: tempDir.path,
      action: AuditAction.create,
      entity: AuditEntity.transaction,
      id: 'tx_cloud_1',
      summary: 'Lançamento em conta nuvem: Supermercado (R\$ 120,00)',
      details: {'payee': 'Supermercado', 'amt': -12000},
    );

    // Allow microtask to finish writing
    await Future.delayed(const Duration(milliseconds: 50));

    final localLogs = await AuditLogManager.instance.readRecentLogs(
      dbPath: 'cloud://fabiano@teste.com',
      appSupportDirPath: tempDir.path,
      limit: 10,
    );
    expect(localLogs.isNotEmpty, true);
    expect(localLogs.first.summary.contains('Supermercado'), true);
    expect(localLogs.first.action, AuditAction.create);
    expect(localLogs.first.entity, AuditEntity.transaction);

    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('33. CSVExporter & MoneyStore support account filter, start date, and end date filtering', () {
    final store = MoneyStore(autoBoot: false);
    store.db.accounts.clear();
    store.db.txs.clear();

    final cAcc = Account(id: 'acc_cc', name: 'Conta Corrente', type: 'Corrente', opening: 10000);
    final cardAcc = Account(id: 'acc_card', name: 'Cartão de Crédito', type: kCardType, opening: 0);
    store.db.accounts.addAll([cAcc, cardAcc]);

    final cId = cAcc.id;
    final cardId = cardAcc.id;

    // Cria lançamentos em datas diferentes
    store.db.txs.add(Transaction(id: 't1', acc: cId, date: '2026-01-10', payee: 'Padaria', cat: 'Alimentação', amt: -2500));
    store.db.txs.add(Transaction(id: 't2', acc: cId, date: '2026-02-15', payee: 'Supermercado', cat: 'Alimentação', amt: -15000));
    store.db.txs.add(Transaction(id: 't3', acc: cId, date: '2026-03-20', payee: 'Salário', cat: 'Receita', amt: 500000));
    store.db.txs.add(Transaction(id: 't4', acc: cardId, date: '2026-02-28', payee: 'Restaurante', cat: 'Alimentação', amt: -8000));

    expect(store.db.txs.length, 4);

    // 1. Sem filtros (todos)
    expect(store.countTransactionsForExport(), 4);
    final allCsv = store.exportCSVString();
    expect(allCsv.contains('Padaria'), true);
    expect(allCsv.contains('Supermercado'), true);
    expect(allCsv.contains('Salário'), true);
    expect(allCsv.contains('Restaurante'), true);

    // 2. Filtro por conta
    expect(store.countTransactionsForExport(accountFilterId: cId), 3);
    expect(store.countTransactionsForExport(accountFilterId: cardId), 1);
    final cardCsv = store.exportCSVString(accountFilterId: cardId);
    expect(cardCsv.contains('Restaurante'), true);
    expect(cardCsv.contains('Padaria'), false);

    // 3. Filtro por mês (2026-02-01 até 2026-02-31)
    expect(store.countTransactionsForExport(startDate: '2026-02-01', endDate: '2026-02-31'), 2);
    final febCsv = store.exportCSVString(startDate: '2026-02-01', endDate: '2026-02-31');
    expect(febCsv.contains('Supermercado'), true);
    expect(febCsv.contains('Restaurante'), true);
    expect(febCsv.contains('Padaria'), false);
    expect(febCsv.contains('Salário'), false);

    // 4. Filtro por conta + data início/fim
    expect(store.countTransactionsForExport(accountFilterId: cId, startDate: '2026-02-01', endDate: '2026-02-28'), 1);
    final cFebCsv = store.exportCSVString(accountFilterId: cId, startDate: '2026-02-01', endDate: '2026-02-28');
    expect(cFebCsv.contains('Supermercado'), true);
    expect(cFebCsv.contains('Restaurante'), false);
  });

  test('34. transferDestinationAccounts orders non-cards (fav then regular) followed by credit cards at the end (fav then regular)', () {
    final store = MoneyStore(autoBoot: false);
    store.db.accounts.clear();

    final accNormalFav = Account(id: 'a_norm_fav', name: 'Banco Inter (Fav)', type: 'Corrente', opening: 0, favorite: true);
    final accNormalRegular = Account(id: 'a_norm_reg', name: 'Banco Itaú', type: 'Corrente', opening: 0, favorite: false);
    final cardFav = Account(id: 'c_card_fav', name: 'Nubank Ultravioleta (Fav)', type: kCardType, opening: 0, favorite: true);
    final cardRegular = Account(id: 'c_card_reg', name: 'XP Visa Infinite', type: kCardType, opening: 0, favorite: false);
    final inactiveAcc = Account(id: 'a_inact', name: 'Conta Inativa', type: 'Corrente', opening: 0, inactive: true, favorite: true);

    store.db.accounts.addAll([
      cardRegular,
      accNormalRegular,
      cardFav,
      inactiveAcc,
      accNormalFav,
    ]);

    final destAll = store.transferDestinationAccounts();
    expect(destAll.map((a) => a.id).toList(), [
      'a_norm_fav',
      'a_norm_reg',
      'c_card_fav',
      'c_card_reg',
    ]);

    // Excluindo a conta de origem
    final destExcl = store.transferDestinationAccounts(excludeId: 'a_norm_fav');
    expect(destExcl.map((a) => a.id).toList(), [
      'a_norm_reg',
      'c_card_fav',
      'c_card_reg',
    ]);
  });

  test('35. Recurring transfers create paired transactions with xrec and peer, and handle deletion with scope', () {
    final store = MoneyStore(autoBoot: false);
    store.db.accounts.clear();
    store.db.txs.clear();
    store.db.recs.clear();

    final acc1 = Account(id: 'acc1', name: 'Conta Corrente', type: 'Corrente', opening: 100000);
    final acc2 = Account(id: 'acc2', name: 'Poupança', type: 'Poupança', opening: 0);
    store.db.accounts.addAll([acc1, acc2]);

    // Insere transferência recorrente mensal de R$ 250,00 da acc1 para acc2
    store.addTransaction(
      accId: 'acc1',
      date: '2026-11-01',
      payee: 'Aplicação Mensal',
      catSelection: 'xfer:acc2',
      memo: 'Reserva',
      signedAmt: -25000,
      mode: 'recurring',
      freq: 'monthly',
    );

    // Verifica que a regra foi criada com peer == acc2
    expect(store.db.recs.length, 1);
    final rule = store.db.recs.first;
    expect(rule.acc, 'acc1');
    expect(rule.peer, 'acc2');
    expect(rule.amt, -25000);

    // Verifica que syncRecs() gerou os lançamentos para ambas as contas
    final txsAcc1 = store.db.txs.where((t) => t.acc == 'acc1').toList();
    final txsAcc2 = store.db.txs.where((t) => t.acc == 'acc2').toList();
    expect(txsAcc1.isNotEmpty, true);
    expect(txsAcc2.isNotEmpty, true);
    expect(txsAcc1.length, equals(txsAcc2.length));

    // Primeiro lançamento da acc1
    final firstAcc1 = txsAcc1.firstWhere((t) => t.date == '2026-11-01');
    expect(firstAcc1.amt, -25000);
    expect(firstAcc1.peer, 'acc2');
    expect(firstAcc1.cat, 'Transferência: Poupança');
    expect(firstAcc1.xfer, startsWith('xrec:${rule.id}:'));

    // Lançamento contrapartida na acc2
    final firstAcc2 = txsAcc2.firstWhere((t) => t.date == '2026-11-01');
    expect(firstAcc2.amt, 25000);
    expect(firstAcc2.peer, 'acc1');
    expect(firstAcc2.cat, 'Transferência: Conta Corrente');
    expect(firstAcc2.xfer, equals(firstAcc1.xfer));

    // Exclusão com escopo .all deve remover a regra e todos os lançamentos
    store.deleteTransaction(firstAcc1.id, ScopeChoice.all);
    expect(store.db.recs.isEmpty, true);
    expect(store.db.txs.where((t) => t.recId == rule.id).isEmpty, true);
  });

  testWidgets('36. Transaction edit modal displays transfer button for transfers and series information for installments and recurrences', (tester) async {
    final store = MoneyStore(autoBoot: false);
    store.db.accounts.clear();
    store.db.txs.clear();
    store.db.recs.clear();

    final acc1 = Account(id: 'acc1', name: 'Banco Alpha', type: 'Corrente', opening: 100000);
    final acc2 = Account(id: 'acc2', name: 'Banco Beta', type: 'Poupança', opening: 50000);
    store.db.accounts.addAll([acc1, acc2]);

    // 1. Lançamento Parcelado
    final installmentTx = Transaction(
      id: 'tx_inst_1',
      acc: 'acc1',
      date: '2026-11-10',
      payee: 'Notebook (2/10)',
      cat: 'Eletrônicos',
      memo: 'Compra de trabalho',
      amt: -35000,
      plan: 'plan_xyz',
      pn: 2,
      pt: 10,
    );
    store.db.txs.add(installmentTx);

    // 2. Transferência Recorrente
    final recTransferTx = Transaction(
      id: 'tx_rec_xfer_1',
      acc: 'acc1',
      peer: 'acc2',
      date: '2026-11-12',
      payee: 'Transferência Mensal',
      cat: 'Transferência: Banco Beta',
      memo: 'Aporte',
      amt: -20000,
      xfer: 'xrec:rule_1:3',
      recId: 'rule_1',
      recFreq: 'monthly',
      recSeq: 3,
    );
    store.db.txs.add(recTransferTx);

    // Abrir modal de edição para o lançamento parcelado
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showTransactionEditModal(ctx, store, installmentTx),
            child: const Text('Editar Parcelado'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Editar Parcelado'));
    await tester.pumpAndSettle();

    // Verifica que exibe o banner informativo de parcelamento
    expect(find.textContaining('Lançamento Parcelado • Parcela 2 de 10'), findsOneWidget);
    expect(find.textContaining('Este lançamento faz parte de um plano em 10 parcelas.'), findsOneWidget);

    // Fecha o modal
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    // Abrir modal de edição para a transferência recorrente
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showTransactionEditModal(ctx, store, recTransferTx),
            child: const Text('Editar Transferência'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Editar Transferência'));
    await tester.pumpAndSettle();

    // Verifica que exibe o botão Transferência e o banner informativo de transferência recorrente
    expect(find.text('⇄ Transferência'), findsWidgets);
    expect(find.textContaining('Transferência Recorrente • Mensal (Ocorrência #3)'), findsOneWidget);
    expect(find.text('Conta de Destino da Transferência'), findsOneWidget);
  });

  testWidgets('37. CsvQifCenterModal renders cleanly on mobile screen without overflows across Import and Export tabs', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final store = MoneyStore(autoBoot: false);
    store.db.accounts.add(Account(id: 'acc1', name: 'Banco Inter', type: 'Corrente', opening: 100000));
    store.db.accounts.add(Account(id: 'card1', name: 'Cartão Black', type: 'Cartão de crédito', opening: 0));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showCsvQifCenterModal(ctx, store),
            child: const Text('Abrir Central'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Abrir Central'));
    await tester.pumpAndSettle();

    // Valida aba Importar em tela mobile 360px
    expect(find.text('Importação / Exportação'), findsOneWidget);
    expect(find.text('Importar'), findsOneWidget);
    expect(find.text('Exportar'), findsOneWidget);
    expect(find.textContaining('Importação Geral de Lançamentos'), findsOneWidget);
    expect(find.text('Importar Lançamentos (CSV)...'), findsOneWidget);
    expect(find.text('Importar QIF (Money 99)...'), findsOneWidget);

    // Muda para aba Exportar
    await tester.tap(find.text('Exportar'));
    await tester.pumpAndSettle();

    // Valida aba Exportar em tela mobile 360px
    expect(find.textContaining('Filtros para Exportação de Lançamentos'), findsOneWidget);
    expect(find.text('Tudo'), findsOneWidget);
    expect(find.text('Mês'), findsOneWidget);
    expect(find.text('Período'), findsOneWidget);
    expect(find.text('Exportar Categorias'), findsOneWidget);

    // Fecha o modal
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
    expect(find.text('Importação / Exportação'), findsNothing);
  });

  testWidgets('38. AccountLedgerView quick entry bar displays invoice selector on credit cards and omits on regular accounts', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = MoneyStore(autoBoot: false);
    final cardAccount = Account(
      id: 'card_xp',
      name: 'Cartão XP',
      type: kCardType,
      opening: 0,
      card: CardConfig(
        closeDay: 10,
        dueDay: 20,
        pay: 'acc_checking',
      ),
    );
    final bankAccount = Account(
      id: 'acc_checking',
      name: 'Banco Itaú',
      type: 'Corrente',
      opening: 500000,
    );
    store.db.accounts.addAll([cardAccount, bankAccount]);

    // 1. Testa tela de conta bancária (não deve ter seletor de fatura)
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AccountLedgerView(store: store, account: bankAccount),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Fatura do Cartão (Competência)'), findsNothing);

    // 2. Testa tela de fatura de cartão de crédito no desktop (deve exibir o seletor de fatura e padrão)
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AccountLedgerView(store: store, account: cardAccount),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Fatura do Cartão (Competência)'), findsOneWidget);
    expect(find.textContaining('[Padrão]'), findsOneWidget);

    // 3. Testa no mobile (360x740): abre recolhida, clica no botão de adicionar e exibe o seletor de fatura
    tester.view.physicalSize = const Size(360, 740);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AccountLedgerView(store: store, account: cardAccount),
      ),
    ));
    await tester.pumpAndSettle();

    // No mobile, a barra inicia recolhida
    expect(find.text('Fatura do Cartão (Competência)'), findsNothing);

    // Ao tocar no botão de inserção rápida, a barra se expande
    await tester.tap(find.byTooltip('Novo Lançamento nesta conta'));
    await tester.pumpAndSettle();

    expect(find.text('Fatura do Cartão (Competência)'), findsOneWidget);
    expect(find.textContaining('[Padrão]'), findsOneWidget);
  });

  testWidgets(
      '39. Batch edit category indentation, quick action buttons on hidden inline bar, transfer payee auto-fill, and bank logo picker search',
      (WidgetTester tester) async {
    final store = MoneyStore(autoBoot: false);
    store.db = Database(
      v: 7,
      accounts: [
        Account(
          id: 'acc1',
          name: 'Conta Corrente',
          type: 'Corrente',
          opening: 100000,
        ),
        Account(
          id: 'acc2',
          name: 'Poupança',
          type: 'Poupança',
          opening: 50000,
        ),
      ],
      txs: [
        Transaction(
          id: 't1',
          acc: 'acc1',
          date: '2026-11-01',
          payee: 'Mercado',
          cat: 'Alimentação:Mercado',
          amt: -5000,
        ),
      ],
      cats: [
        CategoryItem(
          name: 'Alimentação',
          type: 'Despesa',
        ),
        CategoryItem(
          name: 'Mercado',
          parent: 'Alimentação',
          type: 'Despesa',
        ),
        CategoryItem(
          name: 'Restaurante',
          parent: 'Alimentação',
          type: 'Despesa',
        ),
        CategoryItem(
          name: 'Salário',
          type: 'Receita',
        ),
      ],
    );

    // 1. Edição em Lote: dropdown de categoria mostra subcategorias indentadas com "↳"
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BatchEditTransactionsModal(
          store: store,
          selectedIds: const {'t1'},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Habilita a seção de categoria
    await tester.tap(find.text('Categoria'));
    await tester.pumpAndSettle();

    // Abre o dropdown de categorias
    final catDropdown = find.byType(DropdownButtonFormField<String>).first;
    await tester.tap(catDropdown);
    await tester.pumpAndSettle();

    // Verifica que existe opção de subcategoria indentada
    expect(find.textContaining('↳ Mercado'), findsWidgets);
    expect(find.textContaining('↳ Restaurante'), findsWidgets);
    // Fecha o dropdown selecionando Restaurante
    await tester.tap(find.textContaining('↳ Restaurante').last);
    await tester.pumpAndSettle();

    // Habilita a seção de Data na Edição em Lote, verifica campo digitável e abre o calendário sem erro
    await tester.ensureVisible(find.text('Data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Data'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Escolher data no calendário'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Escolher data no calendário'), findsOneWidget);
    await tester.tap(find.byTooltip('Escolher data no calendário'));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarDatePicker), findsOneWidget);
    // Fecha o DatePicker
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // 2. Extrato: quando showInlineTransactionEntry = false, exibe os 3 botões de ação rápida após Editar Conta
    store.showInlineTransactionEntry = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AccountLedgerView(
          store: store,
          account: store.db.accounts.first,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Nova Despesa'), findsOneWidget);
    expect(find.byTooltip('Nova Receita'), findsOneWidget);
    expect(find.byTooltip('Nova Transferência'), findsOneWidget);

    // 3. Ao abrir com Nova Transferência, preenche descrição com "Transferência" e não busca sugestões de histórico
    await tester.tap(find.byTooltip('Nova Transferência'));
    await tester.pumpAndSettle();

    // Campo de descrição deve ter "Transferência"
    expect(find.widgetWithText(TextField, 'Transferência'), findsOneWidget);

    // Ao digitar no campo de descrição enquanto está em transferência, não abre histórico
    await tester.enterText(find.widgetWithText(TextField, 'Transferência'), 'Transferência Pix');
    await tester.pumpAndSettle();
    expect(find.text('Histórico recente'), findsNothing);

    // Fecha o modal de novo lançamento
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    // 4. Edição de conta: Busca no seletor de logos não reseta e mantém o filtro
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showAccountModal(
              ctx,
              store,
              editingAccount: store.db.accounts.first,
            ),
            child: const Text('Abrir Modal'),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Abrir Modal'));
    await tester.pumpAndSettle();

    // Clica para escolher/trocar o logo
    await tester.tap(find.byIcon(Icons.account_balance));
    await tester.pumpAndSettle();

    // Modal de logos aberto
    expect(find.text('Escolher Logo do Banco'), findsOneWidget);
    final searchInput = find.widgetWithText(TextField, 'Buscar banco...');
    expect(searchInput, findsOneWidget);

    // Digita "Nubank" na busca
    await tester.enterText(searchInput, 'Nubank');
    await tester.pumpAndSettle();

    // Verifica que mantém o texto pesquisado e exibe o logo do Nubank
    expect(find.widgetWithText(TextField, 'Nubank'), findsOneWidget);
    expect(find.widgetWithText(InkWell, 'Nubank'), findsOneWidget);
    expect(find.byIcon(Icons.clear), findsOneWidget);
  });

  testWidgets(
      '40. Payee suggestions respect isExpense (Despesa vs Receita), lookback window, and account scope setting',
      (WidgetTester tester) async {
    final nowIso = todayISO();
    final oldIso = '2020-01-01';

    final store = MoneyStore(autoBoot: false);
    store.payeeSuggestionIncludeAccount = false;
    store.payeeSuggestionLookbackDays = 90;

    store.db = Database(
      v: 7,
      accounts: [
        Account(id: 'acc_a', name: 'Banco A', type: 'Corrente', opening: 100000),
        Account(id: 'acc_b', name: 'Banco B', type: 'Poupança', opening: 50000),
      ],
      txs: [
        // Despesa recente no Banco B
        Transaction(
          id: 't_exp',
          acc: 'acc_b',
          date: nowIso,
          payee: 'Posto Estrela',
          cat: 'Transporte:Combustível',
          amt: -15000,
        ),
        // Receita recente no Banco A
        Transaction(
          id: 't_inc',
          acc: 'acc_a',
          date: nowIso,
          payee: 'Posto Reembolso',
          cat: 'Renda:Outros',
          amt: 20000,
        ),
        // Despesa antiga (fora dos 90 dias)
        Transaction(
          id: 't_old',
          acc: 'acc_a',
          date: oldIso,
          payee: 'Livraria Velha',
          cat: 'Educação:Livros',
          amt: -5000,
        ),
      ],
      cats: [
        CategoryItem(name: 'Transporte', type: 'Despesa'),
        CategoryItem(name: 'Combustível', parent: 'Transporte', type: 'Despesa'),
        CategoryItem(name: 'Educação', type: 'Despesa'),
        CategoryItem(name: 'Livros', parent: 'Educação', type: 'Despesa'),
        CategoryItem(name: 'Renda', type: 'Receita'),
        CategoryItem(name: 'Outros', parent: 'Renda', type: 'Receita'),
      ],
    );
    store.rebuildIndexes();

    // 1. Testa filtro por tipo (Despesa vs. Receita)
    final expSuggestions = store.payeeSuggestions('Posto', isExpense: true);
    expect(expSuggestions.length, 1);
    expect(expSuggestions.first.name, 'Posto Estrela');

    final incSuggestions = store.payeeSuggestions('Posto', isExpense: false);
    expect(incSuggestions.length, 1);
    expect(incSuggestions.first.name, 'Posto Reembolso');

    // 2. Testa janela de lookback (90 dias vs Todo o histórico)
    final oldUnder90 = store.payeeSuggestions('Livraria', isExpense: true);
    expect(oldUnder90, isEmpty);

    store.setPayeeSuggestionLookbackDays(0); // Todo o histórico
    final oldUnderAll = store.payeeSuggestions('Livraria', isExpense: true);
    expect(oldUnderAll.length, 1);
    expect(oldUnderAll.first.name, 'Livraria Velha');
    store.setPayeeSuggestionLookbackDays(90);

    // 3. Testa modal de inserção: quando payeeSuggestionIncludeAccount = false (padrão),
    // ao selecionar sugestão, NÃO altera a conta selecionada
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showTransactionCreateModal(
              ctx,
              store,
              initialAccountId: 'acc_a',
              initialTxType: 'expense',
            ),
            child: const Text('Abrir Modal'),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Abrir Modal'));
    await tester.pumpAndSettle();

    // Digita "Posto" no Favorecido
    final payeeField = find.widgetWithText(TextField, 'Favorecido / Descrição');
    await tester.enterText(payeeField, 'Posto');
    await tester.pumpAndSettle();

    // Chip de sugestão não exibe o nome da conta quando includeAccount = false
    expect(find.text('Posto Estrela • Transporte:Combustível'), findsOneWidget);
    expect(find.textContaining('Banco B'), findsNothing);

    // Clica na sugestão
    await tester.tap(find.text('Posto Estrela • Transporte:Combustível'));
    await tester.pumpAndSettle();

    // Conta permanece Banco A (acc_a), não muda para Banco B
    expect(find.textContaining('Banco A (Corrente)'), findsOneWidget);

    // Fecha o modal
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    // 4. Ativa payeeSuggestionIncludeAccount = true: ao selecionar sugestão, altera a conta para Banco B
    store.setPayeeSuggestionIncludeAccount(true);

    await tester.tap(find.text('Abrir Modal'));
    await tester.pumpAndSettle();

    final payeeField2 = find.widgetWithText(TextField, 'Favorecido / Descrição');
    await tester.enterText(payeeField2, 'Posto');
    await tester.pumpAndSettle();

    // Agora o chip mostra a conta
    expect(find.text('Posto Estrela • Transporte:Combustível • Banco B'), findsOneWidget);

    // Clica na sugestão
    await tester.tap(find.text('Posto Estrela • Transporte:Combustível • Banco B'));
    await tester.pumpAndSettle();

    // Conta alterada para Banco B
    expect(find.textContaining('Banco B (Poupança)'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    // 5. Verifica renderização dos controles na SettingsView
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SettingsView(store: store),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Preenchimento Automático por Histórico'),
      300,
    );
    expect(find.text('Preenchimento Automático por Histórico'), findsOneWidget);
    expect(find.text('Período do Histórico para Sugestões'), findsOneWidget);
  });

  test('41. Budget migration and auto-reconciliation on parent category rename', () {
    final store = MoneyStore(autoBoot: false);

    // 1. Cria categoria pai e subcategoria com limites
    store.saveCategory(name: 'Alimentação', type: 'Despesa');
    store.saveCategory(name: 'Restaurante', parent: 'Alimentação', type: 'Despesa');
    store.setBudget('Alimentação', 150000);
    store.setBudget('Alimentação › Restaurante', 60000);

    expect(store.db.budgets['Alimentação'], 150000);
    expect(store.db.budgets['Alimentação › Restaurante'], 60000);

    // 2. Renomeia categoria pai para "Comida & Mercado"
    store.saveCategory(
      editingPath: 'Alimentação',
      name: 'Comida & Mercado',
      type: 'Despesa',
    );

    // Verifica se pai e subcategorias foram renomeadas no db.budgets
    expect(store.db.budgets.containsKey('Alimentação'), isFalse);
    expect(store.db.budgets.containsKey('Alimentação › Restaurante'), isFalse);
    expect(store.db.budgets['Comida & Mercado'], 150000);
    expect(store.db.budgets['Comida & Mercado › Restaurante'], 60000);

    // 3. Simula dados legados com chave órfã (ex: "Moradia › Taxa Condominial" onde "Moradia" virou "Habitação")
    store.saveCategory(name: 'Habitação', type: 'Despesa');
    store.saveCategory(name: 'Taxa Condominial', parent: 'Habitação', type: 'Despesa');
    store.db.budgets['Moradia › Taxa Condominial'] = 90000; // órfão antigo

    final reconciled = store.sanitizeAndReconcileBudgets();
    expect(reconciled, greaterThanOrEqualTo(1));
    expect(store.db.budgets.containsKey('Moradia › Taxa Condominial'), isFalse);
    expect(store.db.budgets['Habitação › Taxa Condominial'], 90000);
  });

  testWidgets('42. Blocked categories reset budget to zero and are excluded from BudgetView', (tester) async {
    final store = MoneyStore(autoBoot: false);

    // Cria categoria e subcategoria com limites
    store.saveCategory(name: 'Lazer', type: 'Despesa');
    store.saveCategory(name: 'Cinema', parent: 'Lazer', type: 'Despesa');
    store.setBudget('Lazer', 20000);
    store.setBudget('Lazer › Cinema', 10000);

    expect(store.db.budgets['Lazer'], 20000);
    expect(store.db.budgets['Lazer › Cinema'], 10000);

    // Bloqueia a categoria pai via saveCategory
    store.saveCategory(
      editingPath: 'Lazer',
      name: 'Lazer',
      type: 'Despesa',
      blocked: true,
    );

    // Limites foram zerados (removidos de db.budgets)
    expect(store.db.budgets.containsKey('Lazer'), isFalse);
    expect(store.db.budgets.containsKey('Lazer › Cinema'), isFalse);

    // Renderiza BudgetView e garante que "Lazer" não aparece
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BudgetView(store: store),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Lazer'), findsNothing);
    expect(find.text('↳ Cinema'), findsNothing);
  });
}

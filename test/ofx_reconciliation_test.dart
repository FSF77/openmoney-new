import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmoney/models/openmoney_models.dart';
import 'package:openmoney/services/importers_exporters.dart';
import 'package:openmoney/services/ofx_reconciliation_service.dart';
import 'package:openmoney/services/sync_engine.dart';
import 'package:openmoney/store/money_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MoneyStore makeStore({
    required List<Account> accounts,
    List<Transaction>? txs,
  }) {
    final store = MoneyStore();
    store.db = Database(
      accounts: accounts,
      cats: [
        CategoryItem(name: 'Alimentação', type: 'Despesa'),
        CategoryItem(name: 'Mercado', parent: 'Alimentação', type: 'Despesa'),
        CategoryItem(name: 'Casa', type: 'Despesa'),
        CategoryItem(name: 'Eletricidade', parent: 'Casa', type: 'Despesa'),
        CategoryItem(name: 'Condomínio', parent: 'Casa', type: 'Despesa'),
        CategoryItem(name: 'Telefonia', parent: 'Casa', type: 'Despesa'),
        CategoryItem(name: 'Assinaturas e Serviços', type: 'Despesa'),
        CategoryItem(name: 'Impostos e Taxas', type: 'Despesa'),
        CategoryItem(name: 'Outros', type: 'Despesa'),
        CategoryItem(name: 'Outras Rendas', type: 'Receita'),
        CategoryItem(name: 'Pró-labore', type: 'Receita'),
      ],
      txs: txs ?? [],
    );
    store.dbPath = '';
    store.markIndexesDirty();
    store.rebuildIndexes();
    return store;
  }

  group('OFX Reconciliation Service & Store Integration', () {
    test('Schema v:7 omite fitid quando nulo/vazio e preserva roundtrip no SyncEngine', () {
      final txWithoutFit = Transaction(
        id: 'tx1',
        acc: 'a1',
        date: '2026-11-10',
        payee: 'Padaria',
        cat: 'Alimentação',
        amt: -1500,
      );
      expect(txWithoutFit.toJson().containsKey('fitid'), isFalse);

      final txWithFit = Transaction(
        id: 'tx2',
        acc: 'a1',
        date: '2026-11-15',
        payee: 'Cloudflare',
        cat: 'Assinaturas e Serviços',
        amt: -2925,
        rec: true,
        fitid: '6af859e5-6979-4f89-b26a-5b5953f7825c|2026-11-15|-2925',
      );
      final jsonMap = txWithFit.toJson();
      expect(jsonMap['fitid'], '6af859e5-6979-4f89-b26a-5b5953f7825c|2026-11-15|-2925');
      final decoded = Transaction.fromJson(jsonMap);
      expect(decoded.fitid, txWithFit.fitid);

      final db = Database(
        accounts: [Account(id: 'a1', name: 'Nu', type: 'Corrente', opening: 0)],
        txs: [txWithFit],
      );
      final baseline = <String, String>{};
      final diff = SyncEngine.computeDiff(baseline: baseline, db: db, prefs: {});
      expect(diff.any((c) => c.coll == 'txs' && c.id == 'tx2' && c.data['fitid'] == txWithFit.fitid), isTrue);

      final targetDb = Database(accounts: [], txs: []);
      SyncEngine.applyChangesToDatabase(
        db: targetDb,
        prefs: {},
        changes: diff,
        baseline: <String, String>{},
      );
      expect(targetDb.txs.length, 1);
      expect(targetDb.txs.first.fitid, txWithFit.fitid);
    });

    test('Extrato Bancário (STMTRS): limpeza PIX/Boleto, contraparte xfer, pagamento fatura antecipado e LEDGERBAL', () {
      const bankOfx = '''
OFXHEADER:100
DATA:OFXSGML
VERSION:102
ENCODING:UTF-8
CHARSET:NONE
<OFX>
<SIGNONMSGSRSV1>
<SONRS>
<FI>
<ORG>NU PAGAMENTOS S.A.</ORG>
<FID>260</FID>
</FI>
</SONRS>
</SIGNONMSGSRSV1>
<BANKMSGSRSV1>
<STMTTRNRS>
<TRNUID>1</TRNUID>
<STMTRS>
<CURDEF>BRL</CURDEF>
<BANKACCTFROM>
<BANKID>0260</BANKID>
<BRANCHID>1</BRANCHID>
<ACCTID>528486-4</ACCTID>
<ACCTTYPE>CHECKING</ACCTTYPE>
</BANKACCTFROM>
<BANKTRANLIST>
<DTSTART>20261101000000[-3:BRT]</DTSTART>
<DTEND>20261116000000[-3:BRT]</DTEND>
<STMTTRN>
<TRNTYPE>DEBIT</TRNTYPE>
<DTPOSTED>20261101000000[-3:BRT]</DTPOSTED>
<TRNAMT>-7756.94</TRNAMT>
<FITID>6ae6ae95-923a-4d93-9972-04d7ce7f748e</FITID>
<MEMO>Pagamento de fatura</MEMO>
</STMTTRN>
<STMTTRN>
<TRNTYPE>DEBIT</TRNTYPE>
<DTPOSTED>20261101000000[-3:BRT]</DTPOSTED>
<TRNAMT>-330.63</TRNAMT>
<FITID>6ae6b079-966f-4d80-bc05-ca5523d466ab</FITID>
<MEMO>Transferência enviada pelo Pix - ENEL DISTRIBUICAO SAO PAULO - 61.695.227/0001-93 - ITAÚ UNIBANCO S.A. (0341) Agência: 911 Conta: 4486-5</MEMO>
</STMTTRN>
<STMTTRN>
<TRNTYPE>DEBIT</TRNTYPE>
<DTPOSTED>20261105000000[-3:BRT]</DTPOSTED>
<TRNAMT>-777.51</TRNAMT>
<FITID>6aecd3a5-87af-4119-bc57-7c8f3cdf31e8</FITID>
<MEMO>Pagamento de boleto efetuado - CONDOMINIO RESIDENCIAL ONIX</MEMO>
</STMTTRN>
<STMTTRN>
<TRNTYPE>CREDIT</TRNTYPE>
<DTPOSTED>20261115000000[-3:BRT]</DTPOSTED>
<TRNAMT>6.87</TRNAMT>
<FITID>6af99b90-d697-46c8-8fd8-e8ff3eb8c153</FITID>
<MEMO>Transferência recebida pelo Pix via Open Banking - FABIANO DE SOUZA FERNANDES - •••.914.938-•• - ITAÚ UNIBANCO S.A. (0341) Agência: 7847 Conta: 16872-6</MEMO>
</STMTTRN>
<STMTTRN>
<TRNTYPE>DEBIT</TRNTYPE>
<DTPOSTED>20261115000000[-3:BRT]</DTPOSTED>
<TRNAMT>-553.74</TRNAMT>
<FITID>6afa4f49-7a15-49c0-accf-27b215d6a72e</FITID>
<MEMO>Transferência enviada pelo Pix - SEFAZ SP / IPVA Honda WR-V 4/5 (DIRETORIA GERAL DE FINANCAS - DGFIN - 46.377.222/0003-90 - BCO DO BRASIL S.A. (0001) Agência: 1897 Conta: 1300001-2)</MEMO>
</STMTTRN>
</BANKTRANLIST>
<LEDGERBAL>
<BALAMT>497.15</BALAMT>
<DTASOF>20261116000000[-3:BRT]</DTASOF>
</LEDGERBAL>
</STMTRS>
</STMTTRNRS>
</BANKMSGSRSV1>
</OFX>
''';

      final nuAccount = Account(
        id: 'acc_nu',
        name: 'Nubank',
        type: 'Corrente',
        opening: 990910, // Saldo inicial ajustado para que após os movimentos feche em R$ 497,15
        bankCode: '260',
        accountNumber: '528486-4',
      );
      final itauAccount = Account(
        id: 'acc_itau',
        name: 'Itaú Personalité',
        type: 'Corrente',
        opening: 100000,
        bankCode: '341',
        agency: '7847',
        accountNumber: '16872-6',
      );
      final nuCard = Account(
        id: 'card_nu',
        name: 'Cartão Nubank',
        type: kCardType,
        opening: 0,
        card: CardConfig(closeDay: 28, dueDay: 5, pay: 'acc_nu'),
      );

      final store = makeStore(
        accounts: [nuAccount, itauAccount, nuCard],
        txs: [
          // Compra anterior no cartão que gera auto pagamento em 2026-11-05 de -7756.94 na Nu
          Transaction(
            id: 'tx_prev_card',
            acc: 'card_nu',
            date: '2026-10-15',
            payee: 'Compras Outubro',
            cat: 'Outros',
            amt: -775694,
            rec: true,
            ik: '2026-11',
          ),
          // Enel já lançada manualmente como pendente em 2026-11-02 (1 dia depois do banco)
          Transaction(
            id: 'tx_enel_manual',
            acc: 'acc_nu',
            date: '2026-11-02',
            payee: 'Energia Elétrica',
            cat: 'Casa › Eletricidade',
            amt: -33063,
            rec: false,
          ),
          // Envelope de previsão no mesmo valor de -553,74 NÃO deve ser consumido!
          Transaction(
            id: 'tx_pred',
            acc: 'acc_nu',
            date: '2026-11-15',
            payee: 'Previsão Impostos',
            cat: 'Impostos e Taxas',
            amt: -55374,
            rec: false,
          ),
        ],
      );
      store.syncCards(settleCardInvoices: false);
      // Garante que a perna automática da fatura de nov está pendente na conta corrente em 2026-11-05
      final autoPayIdx = store.db.txs.indexWhere((t) => t.id == 'inv:card_nu:2026-11:p');
      expect(autoPayIdx, isNot(-1));
      store.db.txs[autoPayIdx].rec = false;
      store.markIndexesDirty();

      final stmts = OfxReconciliationService.parseBytes(Uint8List.fromList(utf8.encode(bankOfx)));
      expect(stmts.length, 1);
      final stmt = stmts.first;
      expect(stmt.isCreditCard, isFalse);
      expect(stmt.ledgerBalanceCents, 49715);

      final accDetection = OfxReconciliationService.detectTargetAccount(
        statement: stmt,
        accounts: store.db.accounts,
      );
      expect(accDetection.accountId, 'acc_nu');
      expect(accDetection.autoMatched, isTrue);

      final drafts = OfxReconciliationService.buildReconciliationDrafts(
        statement: stmt,
        targetAccountId: 'acc_nu',
        invertSigns: false,
        defaultUpdateDateOnMatch: true,
        store: store,
      );
      expect(drafts.length, 5);

      // 1) Pagamento de fatura em 01/11 casou com autoTx de 05/11 (±7 dias)!
      final dPay = drafts[0];
      expect(dPay.action, OfxReconcileAction.reconcileExisting);
      expect(dPay.matchedTxId, 'inv:card_nu:2026-11:p');
      expect(dPay.updateDateOnMatch, isTrue);

      // 2) Enel preservando categoria/descrição do usuário e conciliando
      final dEnel = drafts[1];
      expect(dEnel.raw.cleanPayee, 'ENEL DISTRIBUICAO SAO PAULO');
      expect(dEnel.raw.cleanMemo, contains('61.695.227/0001-93'));
      expect(dEnel.action, OfxReconcileAction.reconcileExisting);
      expect(dEnel.matchedTxId, 'tx_enel_manual');

      // 3) Condomínio novo
      final dCond = drafts[2];
      expect(dCond.raw.cleanPayee, 'CONDOMINIO RESIDENCIAL ONIX');
      expect(dCond.action, OfxReconcileAction.createNew);

      // 4) PIX Open Banking do próprio Itaú -> auto-detecta transferência xfer:acc_itau!
      final dPixItau = drafts[3];
      expect(dPixItau.raw.cleanPayee, 'FABIANO DE SOUZA FERNANDES');
      expect(dPixItau.action, OfxReconcileAction.createNew);
      expect(dPixItau.categorySelection, 'xfer:acc_itau');

      // 5) SEFAZ IPVA não consome envelope Previsão Impostos!
      final dIpva = drafts[4];
      expect(dIpva.raw.cleanPayee, 'SEFAZ SP / IPVA Honda WR-V 4/5');
      expect(dIpva.action, OfxReconcileAction.createNew);
      expect(dIpva.matchedTxId, isNull);

      // Conferência LEDGERBAL antes de aplicar
      final comp = OfxReconciliationService.computeBalanceComparison(
        statement: stmt,
        targetAccountId: 'acc_nu',
        drafts: drafts,
        store: store,
      );
      // 990910 - 775694 - 33063 - 77751 + 687 - 55374 = 49715!
      expect(comp.projectedReconciledCents, 49715);
      expect(comp.differenceCents, 0);

      // Aplicar conciliação
      final summary = store.applyOFXReconciliationCompat(
        statement: stmt,
        targetAccountId: 'acc_nu',
        drafts: drafts,
      );
      expect(summary.importedCount, 5);

      final enelAfter = store.db.txs.firstWhere((t) => t.id == 'tx_enel_manual');
      expect(enelAfter.payee, 'Energia Elétrica');
      expect(enelAfter.cat, 'Casa › Eletricidade');
      expect(enelAfter.date, '2026-11-01');
      expect(enelAfter.rec, isTrue);
      expect(enelAfter.fitid, isNotNull);

      // Transferência gerou perna espelho conciliada no Itaú
      final itauLegs = store.db.txs.where((t) => t.acc == 'acc_itau').toList();
      expect(itauLegs.length, 1);
      expect(itauLegs.first.amt, -687);
      expect(itauLegs.first.rec, isTrue);

      // Auto pagamento da fatura manteve rec=true e atualizou inv.due para 2026-11-01
      final autoPayAfter = store.db.txs.firstWhere((t) => t.id == 'inv:card_nu:2026-11:p');
      expect(autoPayAfter.rec, isTrue);
      expect(autoPayAfter.date, '2026-11-01');
      expect(store.accById('card_nu')?.invoices?['2026-11']?.due, '2026-11-01');
      expect(store.accById('card_nu')?.invoices?['2026-11']?.manual, isTrue);

      // Idempotência na reimportação do mesmo OFX
      final secondDrafts = OfxReconciliationService.buildReconciliationDrafts(
        statement: stmt,
        targetAccountId: 'acc_nu',
        invertSigns: false,
        defaultUpdateDateOnMatch: true,
        store: store,
      );
      expect(secondDrafts.every((d) => d.action == OfxReconcileAction.ignore && d.isFitIdAlreadyImported), isTrue);
    });

    test('Fatura Cartão (CCSTMTRS): UTF-8 com CHARSET:1252, FITID duplicado (IOF/Estorno), ik, Pagamento recebido e parcelas 1-para-1', () {
      const cardOfx = '''
OFXHEADER:100
DATA:OFXSGML
VERSION:102
ENCODING:USASCII
CHARSET:1252
<OFX>
<SIGNONMSGSRSV1>
<SONRS>
<FI>
<ORG>NU PAGAMENTOS S.A.</ORG>
<FID>260</FID>
</FI>
</SONRS>
</SIGNONMSGSRSV1>
<CREDITCARDMSGSRSV1>
<CCSTMTTRNRS>
<TRNUID>1001</TRNUID>
<CCSTMTRS>
<CURDEF>BRL</CURDEF>
<CCACCTFROM>
<ACCTID>5564a52f-05d6-4cc4-921e-c619097011fd</ACCTID>
</CCACCTFROM>
<BANKTRANLIST>
<DTSTART>20261029000000[-3:BRT]</DTSTART>
<DTEND>20261128000000[-3:BRT]</DTEND>
<STMTTRN>
<TRNTYPE>DEBIT</TRNTYPE>
<DTPOSTED>20261117000000[-3:BRT]</DTPOSTED>
<TRNAMT>-89.07</TRNAMT>
<FITID>6afb2e6a-331c-4da2-9083-5bd7aea50625</FITID>
<MEMO>Açougue</MEMO>
</STMTTRN>
<STMTTRN>
<TRNTYPE>CREDIT</TRNTYPE>
<DTPOSTED>20261115000000[-3:BRT]</DTPOSTED>
<TRNAMT>1.02</TRNAMT>
<FITID>6af97bfa-eee3-45e5-910b-010f7768d3f4</FITID>
<MEMO>IOF de volta de Cloudflare</MEMO>
</STMTTRN>
<STMTTRN>
<TRNTYPE>DEBIT</TRNTYPE>
<DTPOSTED>20261115000000[-3:BRT]</DTPOSTED>
<TRNAMT>-1.02</TRNAMT>
<FITID>6af859e5-6979-4f89-b26a-5b5953f7825c</FITID>
<MEMO>IOF de compra internacional</MEMO>
</STMTTRN>
<STMTTRN>
<TRNTYPE>DEBIT</TRNTYPE>
<DTPOSTED>20261115000000[-3:BRT]</DTPOSTED>
<TRNAMT>-29.25</TRNAMT>
<FITID>6af859e5-6979-4f89-b26a-5b5953f7825c</FITID>
<MEMO>Cloudflare</MEMO>
</STMTTRN>
<STMTTRN>
<TRNTYPE>CREDIT</TRNTYPE>
<DTPOSTED>20261108000000[-3:BRT]</DTPOSTED>
<TRNAMT>638.52</TRNAMT>
<FITID>6aecc40d-4700-440c-9519-0172cb3067e8</FITID>
<MEMO>Estorno de compra (Momô Sushi)</MEMO>
</STMTTRN>
<STMTTRN>
<TRNTYPE>DEBIT</TRNTYPE>
<DTPOSTED>20261108000000[-3:BRT]</DTPOSTED>
<TRNAMT>-638.52</TRNAMT>
<FITID>6aecc40d-4700-440c-9519-0172cb3067e8</FITID>
<MEMO>Reversão do Crédito de confiança de Momô Sushi</MEMO>
</STMTTRN>
<STMTTRN>
<TRNTYPE>CREDIT</TRNTYPE>
<DTPOSTED>20261106000000[-3:BRT]</DTPOSTED>
<TRNAMT>638.52</TRNAMT>
<FITID>6aecc40d-4700-440c-9519-0172cb3067e8</FITID>
<MEMO>Crédito de confiança de Momô Sushi</MEMO>
</STMTTRN>
<STMTTRN>
<TRNTYPE>DEBIT</TRNTYPE>
<DTPOSTED>20261106000000[-3:BRT]</DTPOSTED>
<TRNAMT>-638.52</TRNAMT>
<FITID>6aecc40d-4700-440c-9519-0172cb3067e8</FITID>
<MEMO>Momô Sushi</MEMO>
</STMTTRN>
<STMTTRN>
<TRNTYPE>CREDIT</TRNTYPE>
<DTPOSTED>20261101000000[-3:BRT]</DTPOSTED>
<TRNAMT>7756.94</TRNAMT>
<FITID>6ae6ae95-923a-4d93-9972-04d7ce7f748e</FITID>
<MEMO>Pagamento recebido</MEMO>
</STMTTRN>
<STMTTRN>
<TRNTYPE>DEBIT</TRNTYPE>
<DTPOSTED>20261029000000[-3:BRT]</DTPOSTED>
<TRNAMT>-30.00</TRNAMT>
<FITID>6a98d880-f052-446e-8324-221fb197b289</FITID>
<MEMO>Vivo Easy Light (11) 97552-4424 - Parcela 3/12</MEMO>
</STMTTRN>
<STMTTRN>
<TRNTYPE>DEBIT</TRNTYPE>
<DTPOSTED>20261029000000[-3:BRT]</DTPOSTED>
<TRNAMT>-30.00</TRNAMT>
<FITID>6a98c4b1-4001-4e3e-b723-a35811c2f594</FITID>
<MEMO>Vivo Easy Light (11) 98772-1559 - Parcela 3/12</MEMO>
</STMTTRN>
</BANKTRANLIST>
<LEDGERBAL>
<BALAMT>-178.32</BALAMT>
<DTASOF>20261128000000[-3:BRT]</DTASOF>
</LEDGERBAL>
</CCSTMTRS>
</CCSTMTTRNRS>
</CREDITCARDMSGSRSV1>
</OFX>
''';

      final nuCard = Account(
        id: 'card_nu',
        name: 'Cartão Nubank',
        type: kCardType,
        opening: 0,
        card: CardConfig(closeDay: 28, dueDay: 5, pay: 'a1'),
      );
      final checking = Account(
        id: 'a1',
        name: 'Conta Corrente',
        type: 'Corrente',
        opening: 0,
      );

      final store = makeStore(
        accounts: [checking, nuCard],
        txs: [
          // Duas parcelas 3/12 lançadas com datas diferentes dentro da fatura 2026-12!
          Transaction(
            id: 'tx_vivo_1',
            acc: 'card_nu',
            date: '2026-11-12',
            payee: 'Vivo Easy 97552-4424 (3/12)',
            cat: 'Casa › Telefonia',
            amt: -3000,
            rec: false,
            ik: '2026-12',
            plan: 'p1',
            pn: 3,
            pt: 12,
          ),
          Transaction(
            id: 'tx_vivo_2',
            acc: 'card_nu',
            date: '2026-11-18',
            payee: 'Vivo Easy 98772-1559 (3/12)',
            cat: 'Casa › Telefonia',
            amt: -3000,
            rec: false,
            ik: '2026-12',
            plan: 'p2',
            pn: 3,
            pt: 12,
          ),
        ],
      );

      final stmts = OfxReconciliationService.parseBytes(Uint8List.fromList(utf8.encode(cardOfx)));
      expect(stmts.length, 1);
      final stmt = stmts.first;
      expect(stmt.isCreditCard, isTrue);
      // UTF-8 preservado mesmo com CHARSET:1252 no header
      expect(stmt.transactions.first.cleanPayee, 'Açougue');
      expect(stmt.transactions[4].rawDescription, contains('Momô Sushi'));

      // FITIDs compostos distintos para IOF/Cloudflare e os 4 registros de Momô Sushi
      final uniqueFits = stmt.transactions.map((t) => t.compositeFitId).toSet();
      expect(uniqueFits.length, stmt.transactions.length);

      // Competência alvo 2026-12 inferida por DTEND + nome do arquivo
      final detectedIk = OfxReconciliationService.detectTargetInvoiceKey(
        statement: stmt,
        cardAccount: nuCard,
        fileName: 'Cartão_Nubank_2026-12-05.ofx',
        currentStoreMonth: '2026-11',
      );
      expect(detectedIk, '2026-12');

      final drafts = OfxReconciliationService.buildReconciliationDrafts(
        statement: stmt,
        targetAccountId: 'card_nu',
        targetInvoiceKey: detectedIk,
        invertSigns: false,
        defaultUpdateDateOnMatch: false,
        store: store,
      );

      // Pagamento recebido (+7756.94) deve ser ignorado automaticamente
      final pagRecebido = drafts.firstWhere((d) => d.raw.memo == 'Pagamento recebido');
      expect(pagRecebido.isInvoicePaymentCredit, isTrue);
      expect(pagRecebido.action, OfxReconcileAction.ignore);

      // As duas parcelas de R$ 30,00 casaram 1-para-1 com os telefones corretos
      final dVivo1 = drafts.firstWhere((d) => d.raw.memo.contains('97552-4424'));
      final dVivo2 = drafts.firstWhere((d) => d.raw.memo.contains('98772-1559'));
      expect(dVivo1.action, OfxReconcileAction.reconcileExisting);
      expect(dVivo1.matchedTxId, 'tx_vivo_1');
      expect(dVivo1.updateDateOnMatch, isFalse);
      expect(dVivo2.action, OfxReconcileAction.reconcileExisting);
      expect(dVivo2.matchedTxId, 'tx_vivo_2');

      // Conferência LEDGERBAL da fatura (-89.07 + 1.02 - 1.02 - 29.25 + 638.52 - 638.52 + 638.52 - 638.52 - 30.00 - 30.00 = -178.32)
      final balComp = OfxReconciliationService.computeBalanceComparison(
        statement: stmt,
        targetAccountId: 'card_nu',
        targetInvoiceKey: detectedIk,
        drafts: drafts,
        store: store,
      );
      expect(balComp.projectedReconciledCents, -17832);
      expect(balComp.differenceCents, 0);

      // Aplicar conciliação
      store.applyOfxReconciliation(
        statement: stmt,
        targetAccountId: 'card_nu',
        targetInvoiceKey: detectedIk,
        drafts: drafts,
      );

      // Todas compras da fatura receberam ik = '2026-12' e rec = true
      final acougue = store.db.txs.firstWhere((t) => t.payee == 'Açougue');
      expect(acougue.ik, '2026-12');
      expect(acougue.rec, isTrue);
      expect(acougue.amt, -8907);

      // As duas parcelas preservam as datas originais (12/11 e 18/11) e foram marcadas como conciliadas
      expect(store.db.txs.firstWhere((t) => t.id == 'tx_vivo_1').date, '2026-11-12');
      expect(store.db.txs.firstWhere((t) => t.id == 'tx_vivo_1').rec, isTrue);
      expect(store.db.txs.firstWhere((t) => t.id == 'tx_vivo_2').rec, isTrue);

      // Pagamento recebido NÃO entrou como crédito na fatura 2026-12
      expect(store.db.txs.any((t) => t.payee == 'Pagamento recebido'), isFalse);

      // Reimportar o mesmo OFX resulta em 100% ignorados
      final reimport = OfxReconciliationService.buildReconciliationDrafts(
        statement: stmt,
        targetAccountId: 'card_nu',
        targetInvoiceKey: detectedIk,
        invertSigns: false,
        defaultUpdateDateOnMatch: false,
        store: store,
      );
      expect(reimport.every((d) => d.action == OfxReconcileAction.ignore), isTrue);
    });
  });
}

extension on MoneyStore {
  ImportSummary applyOFXReconciliationCompat({
    required OfxStatement statement,
    required String targetAccountId,
    required List<OfxReconcileDraftItem> drafts,
  }) =>
      applyOfxReconciliation(
        statement: statement,
        targetAccountId: targetAccountId,
        drafts: drafts,
      );
}

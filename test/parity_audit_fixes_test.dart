import 'package:flutter_test/flutter_test.dart';
import 'package:openmoney/models/openmoney_models.dart';
import 'package:openmoney/store/money_store.dart';

void main() {
  group('Auditoria Técnica: Paridade Estrita Swift ↔ Flutter (ADRs 001 a 006)', () {
    test('ADR 001/002: Database inicializa com Schema v: 7 por padrão', () {
      final db = Database();
      expect(db.v, 7);
      expect(db.predMode, 'month');
    });

    test('ADR 003: isVigenteInvoice calcula vigência por datas com paridade ao Swift', () {
      final cardCfg = CardConfig(
        closeDay: 23,
        dueDay: 3,
        pay: 'a1',
      );

      // Cenário A: Data de referência no ciclo atual aberto
      // Hoje: 2026-10-15 (antes do fechamento em 23/10)
      // Ciclo aberto atual para novas compras é 2026-11 (vence 03/11/2026 pois dueDay <= closeDay)
      final refDateA = '2026-10-15';
      final currentOpenKeyA = invKeyFor(cardCfg, refDateA);
      expect(currentOpenKeyA, '2026-11');
      expect(
        isVigenteInvoice(
          cardCfg: cardCfg,
          invoiceKey: '2026-11',
          today: refDateA,
        ),
        isTrue,
        reason: 'Fatura do ciclo aberto atual deve ser vigente',
      );

      // Cenário B: Fatura fechada recentemente aguardando quitação até o vencimento
      // Hoje: 2026-10-25 (após fechamento em 23/10, mas antes do vencimento em 03/11)
      // O ciclo aberto para compras agora é 2026-12.
      // Porém, a fatura 2026-11 fechou em 23/10 e vence em 03/11 (23/10 <= 25/10 <= 03/11).
      final refDateB = '2026-10-25';
      final currentOpenKeyB = invKeyFor(cardCfg, refDateB);
      expect(currentOpenKeyB, '2026-12');

      // A fatura 2026-11 não é mais o ciclo aberto, mas ainda é vigente pois está no período de pagamento!
      expect(
        isVigenteInvoice(
          cardCfg: cardCfg,
          invoiceKey: '2026-11',
          today: refDateB,
        ),
        isTrue,
        reason: 'Fatura fechada aguardando vencimento deve ser vigente',
      );

      // Cenário C: Fatura cujo vencimento já passou
      // Hoje: 2026-11-05 (após vencimento em 03/11)
      // A fatura 2026-11 já venceu no passado e não é mais vigente
      final refDateC = '2026-11-05';
      expect(
        isVigenteInvoice(
          cardCfg: cardCfg,
          invoiceKey: '2026-11',
          today: refDateC,
        ),
        isFalse,
        reason: 'Fatura com vencimento decorrido no passado não deve ser vigente',
      );

      // Cenário D: Fatura com customização em Account.invoices
      final account = Account(
        id: 'c1',
        name: 'Cartão Teste',
        type: kCardType,
        opening: 0,
        card: cardCfg,
        invoices: {
          '2026-11': InvoiceInfo(
            close: '2026-10-20',
            due: '2026-10-30',
            pay: 'a1',
            manual: true,
          ),
        },
      );

      // Em 2026-10-25 (<= 2026-10-30), deve ser vigente
      expect(
        isVigenteInvoice(
          cardCfg: cardCfg,
          invoiceKey: '2026-11',
          account: account,
          today: '2026-10-25',
        ),
        isTrue,
      );

      // Em 2026-10-31 (> 2026-10-30), custom invoice venceu -> não vigente
      expect(
        isVigenteInvoice(
          cardCfg: cardCfg,
          invoiceKey: '2026-11',
          account: account,
          today: '2026-10-31',
        ),
        isFalse,
      );
    });

    test('ADR 004/006: syncCards gera lançamentos auto com auto: true e abate saldo previsto quando liquidado', () {
      final store = MoneyStore(autoBoot: false);
      final checking = store.db.accounts.firstWhere((a) => a.id == 'a1');
      store.saveAccount(
        editingId: checking.id,
        name: 'Conta Corrente',
        type: 'Corrente',
        openingCents: 500000, // R$ 5.000,00
        closeDay: 1,
        dueDay: 1,
        payAccId: '',
      );

      store.saveAccount(
        name: 'Cartão Black',
        type: kCardType,
        openingCents: 0,
        closeDay: 10,
        dueDay: 20,
        payAccId: checking.id,
      );
      final card = store.db.accounts.firstWhere((a) => a.type == kCardType);

      // Adiciona compras na fatura 2026-10
      store.addTransaction(
        accId: card.id,
        date: '2026-10-05',
        payee: 'Restaurante',
        catSelection: 'Alimentação',
        memo: '',
        signedAmt: -20000, // R$ 200,00
      );

      // Sincroniza cartões com liquidação ativa
      store.syncCards(settleCardInvoices: true);

      // Verifica se foram gerados os lançamentos com xid inv:card:k e auto == true
      final autoDebit = store.db.txs.firstWhere(
        (t) => t.acc == checking.id && t.card == card.id,
      );
      final autoCredit = store.db.txs.firstWhere(
        (t) => t.acc == card.id && t.xfer == autoDebit.xfer,
      );

      expect(autoDebit.auto, isTrue);
      expect(autoCredit.auto, isTrue);
      expect(autoDebit.xfer!.startsWith('inv:'), isTrue);
      expect(autoDebit.amt, -20000);
      expect(autoCredit.amt, 20000);
      expect(autoCredit.ik, '2026-10');

      // Como o vencimento 2026-10-20 <= hoje (2026-10-31), deve estar conciliado
      expect(autoDebit.rec, isTrue);
      expect(autoCredit.rec, isTrue);

      // O saldo real da conta corrente deve ter descontado os R$ 200,00 (R$ 5.000 - R$ 200 = R$ 4.800)
      expect(store.balance(checking, predicted: false), 480000);

      // O saldo real do cartão deve ser 0 (débito de -200 + crédito de +200)
      expect(store.balance(card, predicted: false), 0);
      expect(store.balance(card, predicted: true), 0);
    });

    test('ADR 005: dueBillItems utiliza isVigenteInvoice para faturas de cartão de crédito', () {
      final store = MoneyStore(autoBoot: false);
      final today = todayISO();

      store.saveAccount(
        name: 'Conta Corrente',
        type: 'Corrente',
        openingCents: 100000,
        closeDay: 1,
        dueDay: 1,
        payAccId: '',
      );
      final regular = store.db.accounts.firstWhere((a) => a.type == 'Corrente');

      store.saveAccount(
        name: 'Cartão XP',
        type: kCardType,
        openingCents: 0,
        closeDay: 23,
        dueDay: 3,
        payAccId: regular.id,
      );
      final card = store.db.accounts.firstWhere((a) => a.type == kCardType);
      final cardCfg = card.card!;

      // 1. Conta a pagar corrente atrasada há 5 dias (rec: false) -> DEVE constar como atrasada
      final pastDate = addDaysDate(today, -5);
      store.db.txs.add(
        Transaction(
          id: 'tx_reg_past',
          acc: regular.id,
          date: pastDate,
          payee: 'Internet Atrasada',
          cat: 'Geral',
          memo: '',
          amt: -10000,
          rec: false,
        ),
      );

      // 2. Compra de cartão com fatura antiga (já decorrido o vencimento e não vigente) -> NÃO deve constar como atrasada
      final oldIk = addMonthsYM(invKeyFor(cardCfg, today), -3);
      store.db.txs.add(
        Transaction(
          id: 'tx_card_antiga',
          acc: card.id,
          date: addDaysDate(today, -90),
          payee: 'Compra Fatura Passada',
          cat: 'Geral',
          memo: '',
          amt: -5000,
          rec: false,
          ik: oldIk,
        ),
      );

      final items = store.dueBillItems(withinDays: 7);
      final itemIds = items.map((i) => i.tx.id).toSet();

      expect(itemIds.contains('tx_reg_past'), isTrue);
      expect(itemIds.contains('tx_card_antiga'), isFalse);

      final regItem = items.firstWhere((i) => i.tx.id == 'tx_reg_past');
      expect(regItem.isOverdue, isTrue);
      expect(regItem.daysUntilDue, -5);
    });
  });
}

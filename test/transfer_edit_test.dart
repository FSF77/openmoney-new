import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmoney/models/openmoney_models.dart';
import 'package:openmoney/store/money_store.dart';
import 'package:openmoney/ui/modals/transaction_modal.dart';

void main() {
  MoneyStore buildStoreWithAccounts(List<Account> accounts) {
    final store = MoneyStore(autoBoot: false);
    store.db.accounts.clear();
    store.db.txs.clear();
    store.db.recs.clear();
    store.db.accounts.addAll(accounts);
    return store;
  }

  group('Edição de Transferências - Store e Modal', () {
    testWidgets(
      '1. Editar valor pela perna de crédito no modal mantém origem como débito e destino como crédito',
      (tester) async {
        final store = buildStoreWithAccounts([
          Account(id: 'a1', name: 'Banco A', type: 'Corrente', opening: 100000),
          Account(id: 'a2', name: 'Banco B', type: 'Poupança', opening: 50000),
        ]);

        store.addTransaction(
          accId: 'a1',
          date: todayISO(),
          payee: 'Transferência A -> B',
          catSelection: 'xfer:a2',
          memo: 'Teste',
          signedAmt: -20000,
        );

        final creditLeg = store.db.txs.firstWhere((t) => t.acc == 'a2');
        expect(creditLeg.amt, 20000);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () => showTransactionEditModal(ctx, store, creditLeg),
                  child: const Text('Editar'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Editar'));
        await tester.pumpAndSettle();

        expect(find.text('Conta de Origem'), findsOneWidget);
        expect(find.text('Conta de Destino da Transferência'), findsOneWidget);

        // Alterar valor de 200,00 para 350,00
        final valorField = find.widgetWithText(TextField, 'Valor (R\$)');
        expect(valorField, findsOneWidget);
        await tester.enterText(valorField, '350,00');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Salvar'));
        await tester.pumpAndSettle();

        final updatedDebit = store.db.txs.firstWhere((t) => t.acc == 'a1');
        final updatedCredit = store.db.txs.firstWhere((t) => t.acc == 'a2');
        expect(updatedDebit.amt, -35000);
        expect(updatedDebit.peer, 'a2');
        expect(updatedCredit.amt, 35000);
        expect(updatedCredit.peer, 'a1');
      },
    );

    testWidgets(
      '2. Trocar Conta de Origem para a antiga conta de destino faz auto-swap e evita mesma conta',
      (tester) async {
        final store = buildStoreWithAccounts([
          Account(id: 'a1', name: 'Banco A', type: 'Corrente', opening: 100000),
          Account(id: 'a2', name: 'Banco B', type: 'Poupança', opening: 50000),
          Account(id: 'a3', name: 'Banco C', type: 'Corrente', opening: 25000),
        ]);

        store.addTransaction(
          accId: 'a1',
          date: todayISO(),
          payee: 'Transferência A -> B',
          catSelection: 'xfer:a2',
          memo: '',
          signedAmt: -15000,
        );

        final debitLeg = store.db.txs.firstWhere((t) => t.acc == 'a1');

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () => showTransactionEditModal(ctx, store, debitLeg),
                  child: const Text('Editar'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Editar'));
        await tester.pumpAndSettle();

        // Troca Conta de Origem de a1 para a2 (antigo destino)
        await tester.tap(find.textContaining('Banco A (Corrente)').first);
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Banco B (Poupança)').last);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Salvar'));
        await tester.pumpAndSettle();

        expect(store.db.txs.length, 2);
        final legB = store.db.txs.firstWhere((t) => t.acc == 'a2');
        final legA = store.db.txs.firstWhere((t) => t.acc == 'a1');
        expect(legB.amt, -15000);
        expect(legB.peer, 'a1');
        expect(legB.cat, 'Transferência: Banco A');
        expect(legA.amt, 15000);
        expect(legA.peer, 'a2');
        expect(legA.cat, 'Transferência: Banco B');
      },
    );

    test(
      '3. Trocar Conta de Destino para terceira conta (C) move a contraparte e atualiza peer/cat',
      () {
        final store = buildStoreWithAccounts([
          Account(id: 'a1', name: 'Banco A', type: 'Corrente', opening: 100000),
          Account(id: 'a2', name: 'Banco B', type: 'Poupança', opening: 50000),
          Account(id: 'a3', name: 'Banco C', type: 'Corrente', opening: 25000),
        ]);

        store.addTransaction(
          accId: 'a1',
          date: '2026-11-20',
          payee: 'Transferência',
          catSelection: 'xfer:a2',
          memo: '',
          signedAmt: -10000,
        );

        final debitLeg = store.db.txs.firstWhere((t) => t.acc == 'a1');
        store.updateTransaction(
          txId: debitLeg.id,
          newAccId: 'a1',
          newDate: '2026-11-20',
          newPayee: 'Transferência',
          newCatSelection: 'xfer:a3',
          newMemo: 'Mudou destino',
          newSignedAmt: -12000,
        );

        expect(store.db.txs.where((t) => t.acc == 'a2'), isEmpty);
        final legA = store.db.txs.firstWhere((t) => t.acc == 'a1');
        final legC = store.db.txs.firstWhere((t) => t.acc == 'a3');
        expect(legA.amt, -12000);
        expect(legA.peer, 'a3');
        expect(legA.cat, 'Transferência: Banco C');
        expect(legC.amt, 12000);
        expect(legC.peer, 'a1');
        expect(legC.cat, 'Transferência: Banco A');
      },
    );

    test(
      '4. Trocar Conta de Origem para terceira conta (C) move a origem e atualiza peer/cat da contraparte',
      () {
        final store = buildStoreWithAccounts([
          Account(id: 'a1', name: 'Banco A', type: 'Corrente', opening: 100000),
          Account(id: 'a2', name: 'Banco B', type: 'Poupança', opening: 50000),
          Account(id: 'a3', name: 'Banco C', type: 'Corrente', opening: 25000),
        ]);

        store.addTransaction(
          accId: 'a1',
          date: '2026-11-20',
          payee: 'Transferência',
          catSelection: 'xfer:a2',
          memo: '',
          signedAmt: -10000,
        );

        final debitLeg = store.db.txs.firstWhere((t) => t.acc == 'a1');
        store.updateTransaction(
          txId: debitLeg.id,
          newAccId: 'a3',
          newDate: '2026-11-20',
          newPayee: 'Transferência',
          newCatSelection: 'xfer:a2',
          newMemo: 'Mudou origem',
          newSignedAmt: -10000,
        );

        expect(store.db.txs.where((t) => t.acc == 'a1'), isEmpty);
        final legC = store.db.txs.firstWhere((t) => t.acc == 'a3');
        final legB = store.db.txs.firstWhere((t) => t.acc == 'a2');
        expect(legC.amt, -10000);
        expect(legC.peer, 'a2');
        expect(legC.cat, 'Transferência: Banco B');
        expect(legB.amt, 10000);
        expect(legB.peer, 'a3');
        expect(legB.cat, 'Transferência: Banco C');
      },
    );

    test(
      '5. Guarda contra auto-transferência rejeita newAccId == newPeerId sem corromper lançamentos',
      () {
        final store = buildStoreWithAccounts([
          Account(id: 'a1', name: 'Banco A', type: 'Corrente', opening: 100000),
          Account(id: 'a2', name: 'Banco B', type: 'Poupança', opening: 50000),
        ]);

        store.addTransaction(
          accId: 'a1',
          date: '2026-11-20',
          payee: 'Transferência',
          catSelection: 'xfer:a2',
          memo: '',
          signedAmt: -10000,
        );

        final debitLeg = store.db.txs.firstWhere((t) => t.acc == 'a1');
        store.updateTransaction(
          txId: debitLeg.id,
          newAccId: 'a2',
          newDate: '2026-11-20',
          newPayee: 'Transferência Inválida',
          newCatSelection: 'xfer:a2',
          newMemo: '',
          newSignedAmt: -99999,
        );

        final legA = store.db.txs.firstWhere((t) => t.acc == 'a1');
        final legB = store.db.txs.firstWhere((t) => t.acc == 'a2');
        expect(legA.amt, -10000);
        expect(legA.peer, 'a2');
        expect(legB.amt, 10000);
        expect(legB.peer, 'a1');
      },
    );

    testWidgets(
      '6. Colisão de prefixo de IDs (a1 vs a10) ao trocar origem não sobrescreve destino a10',
      (tester) async {
        final store = buildStoreWithAccounts([
          Account(id: 'a2', name: 'Banco Origem', type: 'Corrente', opening: 100000),
          Account(id: 'a1', name: 'Banco Um', type: 'Corrente', opening: 50000),
          Account(id: 'a10', name: 'Banco Dez', type: 'Poupança', opening: 25000),
        ]);

        store.addTransaction(
          accId: 'a2',
          date: todayISO(),
          payee: 'Transferência Prefixo',
          catSelection: 'xfer:a10',
          memo: '',
          signedAmt: -30000,
        );

        final debitLeg = store.db.txs.firstWhere((t) => t.acc == 'a2');

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () => showTransactionEditModal(ctx, store, debitLeg),
                  child: const Text('Editar'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Editar'));
        await tester.pumpAndSettle();

        // Trocar origem de a2 para a1 (prefixo de a10)
        await tester.tap(find.textContaining('Banco Origem (Corrente)').first);
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Banco Um (Corrente)').last);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Salvar'));
        await tester.pumpAndSettle();

        final legUm = store.db.txs.firstWhere((t) => t.acc == 'a1');
        final legDez = store.db.txs.firstWhere((t) => t.acc == 'a10');
        expect(legUm.amt, -30000);
        expect(legUm.peer, 'a10');
        expect(legDez.amt, 30000);
        expect(legDez.peer, 'a1');
      },
    );

    test(
      '7. Transferência cross-currency (BRL <-> USD) atualiza valores e rate corretamente',
      () {
        final store = buildStoreWithAccounts([
          Account(id: 'brl', name: 'Itaú', type: 'Corrente', opening: 500000, currency: 'BRL'),
          Account(id: 'usd', name: 'Wise USD', type: 'Corrente', opening: 0, currency: 'USD'),
          Account(id: 'brl2', name: 'Nubank', type: 'Corrente', opening: 200000, currency: 'BRL'),
        ]);
        store.db.rates['USD'] = const CurrencyRateInfo(
          rate: 5.0,
          updatedAt: '2026-11-20T10:00:00Z',
        );

        store.addTransaction(
          accId: 'brl',
          date: '2026-11-20',
          payee: 'Remessa',
          catSelection: 'xfer:usd',
          memo: '',
          signedAmt: -50000,
          peerSignedAmt: 10000,
        );

        final brlLeg = store.db.txs.firstWhere((t) => t.acc == 'brl');
        store.updateTransaction(
          txId: brlLeg.id,
          newAccId: 'brl2',
          newDate: '2026-11-20',
          newPayee: 'Remessa',
          newCatSelection: 'xfer:usd',
          newMemo: 'Editado',
          newSignedAmt: -55000,
          peerSignedAmt: 10000,
        );

        final updatedBrl = store.db.txs.firstWhere((t) => t.acc == 'brl2');
        final updatedUsd = store.db.txs.firstWhere((t) => t.acc == 'usd');
        expect(updatedBrl.amt, -55000);
        expect(updatedBrl.rate, isNull);
        expect(updatedUsd.amt, 10000);
        expect(updatedUsd.peer, 'brl2');
        expect(updatedUsd.rate, closeTo(5.5, 0.0001));
      },
    );

    test(
      '8. Transferência recorrente com ScopeChoice.forward atualiza RecurrenceRule.peer e pernas futuras',
      () {
        final store = buildStoreWithAccounts([
          Account(id: 'a1', name: 'Banco A', type: 'Corrente', opening: 100000),
          Account(id: 'a2', name: 'Banco B', type: 'Poupança', opening: 50000),
          Account(id: 'a3', name: 'Banco C', type: 'Corrente', opening: 25000),
        ]);

        final start = todayISO();
        store.addTransaction(
          accId: 'a1',
          date: start,
          payee: 'Aporte Mensal',
          catSelection: 'xfer:a2',
          memo: '',
          signedAmt: -20000,
          mode: 'recurring',
          freq: 'monthly',
        );

        final rule = store.db.recs.single;
        final seq2Debit = store.db.txs.firstWhere(
          (t) => t.recId == rule.id && t.recSeq == 2 && t.acc == 'a1',
        );

        store.updateTransaction(
          txId: seq2Debit.id,
          newAccId: 'a1',
          newDate: seq2Debit.date,
          newPayee: 'Aporte Mensal Atualizado',
          newCatSelection: 'xfer:a3',
          newMemo: 'Novo destino',
          newSignedAmt: -30000,
          scope: ScopeChoice.forward,
        );

        expect(store.db.recs.single.peer, 'a3');
        expect(store.db.recs.single.amt, -30000);

        final seq2DebitAfter = store.db.txs.firstWhere(
          (t) => t.recId == rule.id && t.recSeq == 2 && !t.id.endsWith(':peer'),
        );
        final seq2PeerAfter = store.db.txs.firstWhere(
          (t) => t.recId == rule.id && t.recSeq == 2 && t.id.endsWith(':peer'),
        );
        expect(seq2DebitAfter.peer, 'a3');
        expect(seq2DebitAfter.amt, -30000);
        expect(seq2PeerAfter.acc, 'a3');
        expect(seq2PeerAfter.peer, 'a1');
        expect(seq2PeerAfter.amt, 30000);

        final seq3PeerAfter = store.db.txs.firstWhere(
          (t) => t.recId == rule.id && t.recSeq == 3 && t.id.endsWith(':peer'),
        );
        expect(seq3PeerAfter.acc, 'a3');
        expect(seq3PeerAfter.peer, 'a1');
        expect(seq3PeerAfter.amt, 30000);
      },
    );

    test(
      '9. Conversão Transferência -> Despesa remove contraparte e Despesa -> Transferência cria contraparte',
      () {
        final store = buildStoreWithAccounts([
          Account(id: 'a1', name: 'Banco A', type: 'Corrente', opening: 100000),
          Account(id: 'a2', name: 'Banco B', type: 'Poupança', opening: 50000),
        ]);

        store.addTransaction(
          accId: 'a1',
          date: '2026-11-20',
          payee: 'Movimento',
          catSelection: 'xfer:a2',
          memo: '',
          signedAmt: -10000,
        );
        expect(store.db.txs.length, 2);

        final leg = store.db.txs.firstWhere((t) => t.acc == 'a1');
        store.updateTransaction(
          txId: leg.id,
          newAccId: 'a1',
          newDate: '2026-11-20',
          newPayee: 'Mercado',
          newCatSelection: 'Alimentação',
          newMemo: '',
          newSignedAmt: -10000,
        );

        expect(store.db.txs.length, 1);
        expect(store.db.txs.single.xfer, isNull);
        expect(store.db.txs.single.peer, isNull);
        expect(store.db.txs.single.cat, 'Alimentação');

        store.updateTransaction(
          txId: store.db.txs.single.id,
          newAccId: 'a1',
          newDate: '2026-11-20',
          newPayee: 'Voltou a ser transferência',
          newCatSelection: 'xfer:a2',
          newMemo: '',
          newSignedAmt: -10000,
        );

        expect(store.db.txs.length, 2);
        final src = store.db.txs.firstWhere((t) => t.acc == 'a1');
        final dst = store.db.txs.firstWhere((t) => t.acc == 'a2');
        expect(src.xfer, isNotNull);
        expect(src.xfer, dst.xfer);
        expect(src.peer, 'a2');
        expect(dst.peer, 'a1');
        expect(dst.amt, 10000);
      },
    );
  });
}

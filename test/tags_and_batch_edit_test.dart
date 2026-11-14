import 'package:flutter_test/flutter_test.dart';
import '../lib/models/openmoney_models.dart';
import '../lib/store/money_store.dart';

void main() {
  group('Tags & Edição em Massa', () {
    MoneyStore makeStore() {
      final store = MoneyStore();
      store.db = Database(
        accounts: [
          Account(
              id: 'a1',
              name: 'Conta Corrente',
              type: 'Corrente',
              opening: 100000),
          Account(
              id: 'a2', name: 'Carteira', type: 'Dinheiro', opening: 50000),
        ],
        cats: [
          CategoryItem(name: 'Alimentação', type: 'Despesa'),
          CategoryItem(name: 'Salário', type: 'Receita'),
          CategoryItem(name: 'Viagem', type: 'Despesa'),
        ],
        txs: [],
      );
      store.markIndexesDirty();
      return store;
    }

    test('Schema v:7 omite tags vazias e preserva roundtrip quando preenchido',
        () {
      final dbEmpty = Database(
        accounts: [
          Account(id: 'a1', name: 'Conta', type: 'Corrente', opening: 0)
        ],
        txs: [
          Transaction(
            id: 't1',
            acc: 'a1',
            date: '2026-11-14',
            payee: 'Café',
            cat: 'Alimentação',
            amt: -1500,
          ),
        ],
      );
      final jsonEmpty = dbEmpty.toJson();
      expect(jsonEmpty.containsKey('tags'), isFalse);
      final txJsonEmpty = (jsonEmpty['txs'] as List).first as Map;
      expect(txJsonEmpty.containsKey('tags'), isFalse);

      final dbWithTags = Database(
        accounts: [
          Account(id: 'a1', name: 'Conta', type: 'Corrente', opening: 0)
        ],
        tags: ['Viagem', 'Trabalho'],
        txs: [
          Transaction(
            id: 't2',
            acc: 'a1',
            date: '2026-11-14',
            payee: 'Hotel',
            cat: 'Viagem',
            amt: -50000,
            tags: ['Viagem', 'Reembolso'],
          ),
        ],
      );
      final parsed = Database.fromJson(dbWithTags.toJson());
      expect(parsed.tags, equals(['Viagem', 'Trabalho']));
      expect(parsed.txs.first.tags, equals(['Viagem', 'Reembolso']));
    });

    test('CRUD de tags: addTag, renameTag, deleteTag e contagem', () {
      final store = makeStore();
      expect(store.addTag('Viagem'), isTrue);
      expect(store.addTag('viagem'), isFalse); // duplicata case-insensitive
      expect(store.addTag('   '), isFalse);

      store.addTransaction(
        accId: 'a1',
        date: '2026-11-14',
        payee: 'Passagem',
        catSelection: 'Viagem',
        memo: '',
        signedAmt: -40000,
        tags: ['Viagem', 'Férias'],
      );
      expect(store.allTags, containsAll(['Férias', 'Viagem']));
      expect(store.transactionCountForTag('viagem'), equals(1));

      expect(store.renameTag('Viagem', 'Turismo'), isTrue);
      expect(store.allTags.contains('Viagem'), isFalse);
      expect(store.allTags.contains('Turismo'), isTrue);
      expect(store.db.txs.first.tags, contains('Turismo'));

      store.deleteTag('Turismo');
      expect(store.allTags.contains('Turismo'), isFalse);
      expect(store.db.txs.first.tags, equals(['Férias']));
    });

    test(
        'consolidatedTransactions aplica filtros de categoria, tag, tipo, conciliação e busca por tag',
        () {
      final store = makeStore();
      store.db.txs.addAll([
        Transaction(
          id: 't1',
          acc: 'a1',
          date: '2026-11-14',
          payee: 'Mercado',
          cat: 'Alimentação',
          amt: -12000,
          rec: true,
          tags: ['Casa'],
        ),
        Transaction(
          id: 't2',
          acc: 'a1',
          date: '2026-11-14',
          payee: 'Empresa XYZ',
          cat: 'Salário',
          amt: 500000,
          rec: false,
        ),
        Transaction(
          id: 't3',
          acc: 'a1',
          peer: 'a2',
          xfer: 'x1',
          date: '2026-11-14',
          payee: 'Saque',
          cat: 'Transferência: Carteira',
          amt: -10000,
          rec: true,
        ),
      ]);
      store.markIndexesDirty();

      final byTag = store.consolidatedTransactions(
        monthYM: '2026-11',
        tagFilter: 'casa',
      );
      expect(byTag.transactions.map((t) => t.id), equals(['t1']));

      final untagged = store.consolidatedTransactions(
        monthYM: '2026-11',
        tagFilter: '__untagged__',
      );
      expect(untagged.transactions.map((t) => t.id), equals(['t2', 't3']));

      final byTypeIncome = store.consolidatedTransactions(
        monthYM: '2026-11',
        typeFilter: 'income',
      );
      expect(byTypeIncome.transactions.map((t) => t.id), equals(['t2']));

      final byTypeTransfer = store.consolidatedTransactions(
        monthYM: '2026-11',
        typeFilter: 'transfer',
      );
      expect(byTypeTransfer.transactions.map((t) => t.id), equals(['t3']));

      final byPending = store.consolidatedTransactions(
        monthYM: '2026-11',
        reconciledFilter: 'pending',
      );
      expect(byPending.transactions.map((t) => t.id), equals(['t2']));

      final bySearchTag = store.consolidatedTransactions(
        monthYM: '2026-11',
        searchQuery: 'casa',
      );
      expect(bySearchTag.transactions.map((t) => t.id), equals(['t1']));
    });

    test(
        'batchUpdateTransactions edita campos selecionados e ignora tx.auto == true',
        () {
      final store = makeStore();
      store.db.txs.addAll([
        Transaction(
          id: 't1',
          acc: 'a1',
          date: '2026-11-10',
          payee: 'Antigo 1',
          cat: 'Alimentação',
          amt: -1000,
          rec: false,
          tags: ['Base'],
        ),
        Transaction(
          id: 't2',
          acc: 'a1',
          date: '2026-11-11',
          payee: 'Antigo 2',
          cat: 'Viagem',
          amt: 2000,
          rec: false,
        ),
        Transaction(
          id: 't_auto',
          acc: 'a1',
          date: '2026-11-12',
          payee: 'Fatura Auto',
          cat: 'Transferência',
          amt: -5000,
          rec: false,
          auto: true,
        ),
      ]);
      store.markIndexesDirty();

      final updated = store.batchUpdateTransactions(
        ids: {'t1', 't2', 't_auto'},
        payload: const BatchTransactionEditPayload(
          applyPayee: true,
          payee: 'Novo Nome',
          applyTags: true,
          tagMode: BatchTagMode.add,
          tags: ['Lote', 'Revisado'],
          applyAmount: true,
          absAmountCents: 3500,
          amountSignMode: BatchAmountSignMode.keepOriginal,
          applyReconciled: true,
          reconciled: true,
        ),
      );

      expect(updated, equals(2));
      final t1 = store.db.txs.firstWhere((t) => t.id == 't1');
      final t2 = store.db.txs.firstWhere((t) => t.id == 't2');
      final tAuto = store.db.txs.firstWhere((t) => t.id == 't_auto');

      expect(t1.payee, equals('Novo Nome'));
      expect(t1.amt, equals(-3500));
      expect(t1.rec, isTrue);
      expect(t1.tags, equals(['Base', 'Lote', 'Revisado']));

      expect(t2.payee, equals('Novo Nome'));
      expect(t2.amt, equals(3500));
      expect(t2.tags, equals(['Lote', 'Revisado']));

      expect(tAuto.payee, equals('Fatura Auto'));
      expect(tAuto.amt, equals(-5000));
    });

    test(
        'batchDeleteTransactionsByIds exclui selecionados e contrapartida de transferência',
        () {
      final store = makeStore();
      store.db.txs.addAll([
        Transaction(
          id: 't1',
          acc: 'a1',
          date: '2026-11-10',
          payee: 'Café',
          cat: 'Alimentação',
          amt: -500,
        ),
        Transaction(
          id: 'x1_a',
          acc: 'a1',
          peer: 'a2',
          xfer: 'xf1',
          date: '2026-11-10',
          payee: 'Saque',
          cat: 'Transferência: Carteira',
          amt: -1000,
        ),
        Transaction(
          id: 'x1_b',
          acc: 'a2',
          peer: 'a1',
          xfer: 'xf1',
          date: '2026-11-10',
          payee: 'Saque',
          cat: 'Transferência: Conta Corrente',
          amt: 1000,
        ),
        Transaction(
          id: 't_auto',
          acc: 'a1',
          date: '2026-11-10',
          payee: 'Auto',
          cat: 'Auto',
          amt: -100,
          auto: true,
        ),
      ]);

      final deleted = store.batchDeleteTransactionsByIds({'t1', 'x1_a', 't_auto'});
      expect(deleted, equals(3));
      expect(store.db.txs.map((t) => t.id).toList(), equals(['t_auto']));
    });

    test('buildMonthlyReport aplica filtro de tag corretamente', () {
      final store = makeStore();
      store.db.txs.addAll([
        Transaction(
          id: 'r1',
          acc: 'a1',
          date: '2026-11-10',
          payee: 'Hotel',
          cat: 'Viagem',
          amt: -30000,
          tags: ['Férias'],
        ),
        Transaction(
          id: 'r2',
          acc: 'a1',
          date: '2026-11-11',
          payee: 'Mercado',
          cat: 'Alimentação',
          amt: -10000,
        ),
        Transaction(
          id: 'r3',
          acc: 'a1',
          date: '2026-11-12',
          payee: 'Bônus',
          cat: 'Salário',
          amt: 50000,
          tags: ['Férias'],
        ),
      ]);
      store.markIndexesDirty();

      final all = store.buildMonthlyReport('2026-11');
      expect(all.totalExpense, equals(40000));
      expect(all.totalIncome, equals(50000));

      final byTag = store.buildMonthlyReport('2026-11', tagFilter: 'férias');
      expect(byTag.totalExpense, equals(30000));
      expect(byTag.totalIncome, equals(50000));

      final untagged =
          store.buildMonthlyReport('2026-11', tagFilter: '__untagged__');
      expect(untagged.totalExpense, equals(10000));
      expect(untagged.totalIncome, equals(0));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import '../lib/models/openmoney_models.dart';
import '../lib/services/sync_engine.dart';

void main() {
  group('SyncEngine v2 — Granular Record Diff & Real-Time Merge', () {
    test('computeDiff detects insert, update, and delete tombstone per record', () {
      final db = Database(
        accounts: [
          Account(id: 'a1', name: 'Conta Corrente', type: 'Corrente', opening: 10000),
        ],
        cats: [
          CategoryItem(name: 'Alimentação', type: 'Despesa'),
        ],
        txs: [
          Transaction(
            id: 'tx1',
            acc: 'a1',
            date: '2026-11-07',
            payee: 'Padaria',
            cat: 'Alimentação',
            amt: -2500,
            rec: true,
            createdAt: 1000.0,
          ),
        ],
      );
      final prefs = <String, dynamic>{'isDarkMode': true};
      final baseline = <String, String>{};

      // Seed initial baseline
      final initialMap = SyncEngine.extractRecordMap(db, prefs);
      initialMap.forEach((k, v) => baseline[k] = v.jsonStr);

      // Sem alterações -> diff vazio
      expect(
        SyncEngine.computeDiff(baseline: baseline, db: db, prefs: prefs),
        isEmpty,
      );

      // 1. Insere novo lançamento tx2
      db.txs.add(
        Transaction(
          id: 'tx2',
          acc: 'a1',
          date: '2026-11-07',
          payee: 'Supermercado',
          cat: 'Alimentação',
          amt: -15000,
          rec: true,
          createdAt: 1001.0,
        ),
      );

      final diffInsert = SyncEngine.computeDiff(
        baseline: baseline,
        db: db,
        prefs: prefs,
      );
      expect(diffInsert.length, 1);
      expect(diffInsert.first.coll, 'txs');
      expect(diffInsert.first.id, 'tx2');
      expect(diffInsert.first.deleted, isFalse);

      // 2. Edita tx1 e remove tx2
      db.txs.firstWhere((t) => t.id == 'tx1').amt = -3200;
      db.txs.removeWhere((t) => t.id == 'tx2');

      final diffUpdateAndDelete = SyncEngine.computeDiff(
        baseline: baseline,
        db: db,
        prefs: prefs,
      );
      expect(diffUpdateAndDelete.length, 2);

      final updatedTx1 =
          diffUpdateAndDelete.firstWhere((c) => c.id == 'tx1');
      expect(updatedTx1.coll, 'txs');
      expect(updatedTx1.deleted, isFalse);
      expect((updatedTx1.data as Map)['amt'], -3200);

      final deletedTx2 =
          diffUpdateAndDelete.firstWhere((c) => c.id == 'tx2');
      expect(deletedTx2.coll, 'txs');
      expect(deletedTx2.deleted, isTrue);
      expect(deletedTx2.data, isNull);
    });

    test('Concurrent edits on two devices merge without overwriting each other and without echo loop', () {
      final dbDeviceA = Database(
        accounts: [
          Account(id: 'a1', name: 'Nubank', type: 'Corrente', opening: 0),
        ],
        txs: [],
      );
      final dbDeviceB = Database(
        accounts: [
          Account(id: 'a1', name: 'Nubank', type: 'Corrente', opening: 0),
        ],
        txs: [],
      );
      final prefsA = <String, dynamic>{'isDarkMode': true};
      final prefsB = <String, dynamic>{'isDarkMode': true};

      final baselineA = <String, String>{};
      final baselineB = <String, String>{};
      SyncEngine.extractRecordMap(dbDeviceA, prefsA)
          .forEach((k, v) => baselineA[k] = v.jsonStr);
      SyncEngine.extractRecordMap(dbDeviceB, prefsB)
          .forEach((k, v) => baselineB[k] = v.jsonStr);

      // Dispositivo A cria tx_A
      dbDeviceA.txs.add(
        Transaction(
          id: 'tx_A',
          acc: 'a1',
          date: '2026-11-07',
          payee: 'Uber',
          cat: 'Transporte',
          amt: -2990,
          rec: true,
          createdAt: 2000.0,
        ),
      );
      final changesFromA = SyncEngine.computeDiff(
        baseline: baselineA,
        db: dbDeviceA,
        prefs: prefsA,
      );

      // Dispositivo B (simultaneamente/offline) cria tx_B e um orçamento
      dbDeviceB.txs.add(
        Transaction(
          id: 'tx_B',
          acc: 'a1',
          date: '2026-11-07',
          payee: 'iFood',
          cat: 'Alimentação',
          amt: -6490,
          rec: true,
          createdAt: 2001.0,
        ),
      );
      dbDeviceB.budgets['Alimentação'] = 120000;
      final changesFromB = SyncEngine.computeDiff(
        baseline: baselineB,
        db: dbDeviceB,
        prefs: prefsB,
      );

      // Dispositivo A recebe delta de B; Dispositivo B recebe delta de A
      SyncEngine.applyChangesToDatabase(
        db: dbDeviceA,
        prefs: prefsA,
        changes: changesFromB,
        baseline: baselineA,
      );
      SyncEngine.applyChangesToDatabase(
        db: dbDeviceB,
        prefs: prefsB,
        changes: changesFromA,
        baseline: baselineB,
      );

      // Ambos os dispositivos convergem com tx_A e tx_B intactos!
      expect(dbDeviceA.txs.map((t) => t.id).toSet(), {'tx_A', 'tx_B'});
      expect(dbDeviceB.txs.map((t) => t.id).toSet(), {'tx_A', 'tx_B'});
      expect(dbDeviceA.budgets['Alimentação'], 120000);
      expect(dbDeviceB.budgets['Alimentação'], 120000);

      // Anti-eco: nenhum dos dois dispositivos gera novo diff após aplicar mudanças remotas
      expect(
        SyncEngine.computeDiff(
            baseline: baselineA, db: dbDeviceA, prefs: prefsA),
        isEmpty,
      );
      expect(
        SyncEngine.computeDiff(
            baseline: baselineB, db: dbDeviceB, prefs: prefsB),
        isEmpty,
      );
    });
  });
}

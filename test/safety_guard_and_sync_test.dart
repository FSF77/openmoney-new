import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmoney/models/openmoney_models.dart';
import 'package:openmoney/services/backup_manager.dart';
import 'package:openmoney/services/cloud_sync_service.dart';
import 'package:openmoney/services/platform_io.dart';
import 'package:openmoney/services/sync_engine.dart';
import 'package:openmoney/store/money_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Safety & Anti-Wipe Guardrails', () {
    test('Bloqueia tentativa de zerar base populada sem confirmação explícita', () {
      bool violationCalled = false;

      expect(
        () => BackupManager.assertSafeDatabaseMutation(
          existingTxCount: 50,
          newTxCount: 0,
          operation: 'Teste Unitário',
          userExplicitlyConfirmed: false,
          onViolation: () {
            violationCalled = true;
          },
        ),
        throwsA(isA<StateError>()),
      );

      expect(violationCalled, isTrue);
    });

    test('Permite zerar base quando usuário confirma explicitamente', () {
      bool violationCalled = false;

      expect(
        () => BackupManager.assertSafeDatabaseMutation(
          existingTxCount: 50,
          newTxCount: 0,
          operation: 'Criar Nova Base Confirmada',
          userExplicitlyConfirmed: true,
          onViolation: () {
            violationCalled = true;
          },
        ),
        returnsNormally,
      );

      expect(violationCalled, isFalse);
    });

    test('Bloqueia queda abrupta não confirmada (>60% dos registros)', () {
      bool violationCalled = false;

      expect(
        () => BackupManager.assertSafeDatabaseMutation(
          existingTxCount: 100,
          newTxCount: 20,
          operation: 'Queda Anômala',
          userExplicitlyConfirmed: false,
          onViolation: () {
            violationCalled = true;
          },
        ),
        throwsA(isA<StateError>()),
      );

      expect(violationCalled, isTrue);
    });

    test('createSafetyBackup gera arquivo imutável com timestamp e motivo', () async {
      final tempDir = Directory.systemTemp.createTempSync('om_safety_test_');
      try {
        final jsonContent = jsonEncode({
          'v': 7,
          'accounts': [{'id': 'a1', 'name': 'Teste', 'type': 'Corrente', 'opening': 1000}],
          'txs': [{'id': 'tx1', 'acc': 'a1', 'date': '2026-11-08', 'amt': -500, 'payee': 'Padaria', 'cat': 'Alimentação'}],
        });

        final backupPath = await BackupManager.instance.createSafetyBackup(
          appSupportDirPath: tempDir.path,
          reason: 'pre-update-v2.3.0-b83',
          jsonContent: jsonContent,
        );

        expect(backupPath, isNotNull);
        expect(File(backupPath!).existsSync(), isTrue);
        expect(backupPath.contains('openmoney-safety-pre-update-v2.3.0-b83'), isTrue);

        final readBack = File(backupPath).readAsStringSync();
        expect(readBack.contains('tx1'), isTrue);
      } finally {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });
  });

  group('StorageMode (Local vs. Cloud) Isolation', () {
    test('Alternância entre Modo Local e Modo Cloud preserva lastLocalDbPath', () async {
      final tempFile = File('${Directory.systemTemp.path}/openmoney_test_db_${DateTime.now().millisecondsSinceEpoch}.json');
      tempFile.writeAsStringSync(jsonEncode({'v': 7, 'accounts': [], 'txs': []}));
      try {
        final store = MoneyStore(autoBoot: false);
        expect(store.storageMode, 'local');
        expect(store.isCloudMode, isFalse);

        await store.switchToLocalMode(path: tempFile.path);
        expect(store.storageMode, 'local');
        expect(store.lastLocalDbPath, tempFile.path);
        expect(store.dbPath, tempFile.path);
      } finally {
        try {
          tempFile.deleteSync();
        } catch (_) {}
      }
    });

    test('Nova base em branco ou vazia inicializa com todas as categorias sugeridas (kDefaultCats)', () {
      final emptyJson = {'v': 7, 'accounts': [{'id': 'a1', 'name': 'Corrente'}], 'cats': [], 'txs': []};
      final db = Database.fromJson(emptyJson);
      expect(db.cats.isNotEmpty, isTrue);
      expect(db.cats.length, kDefaultCats.length);
      expect(db.cats.any((c) => c.name == 'Alimentação'), isTrue);
      expect(db.cats.any((c) => c.name == 'Mercado' && c.parent == 'Alimentação'), isTrue);
      expect(db.cats.any((c) => c.name == 'Renda' && c.type == 'Receita'), isTrue);
    });
  });

  group('Cloud Sync v2 Auth & Verification Flow (Tokens & Proteções)', () {
    test('requestRegister valida formato de e-mail e tamanho mínimo de senha', () async {
      final cloud = CloudSyncService.instance;
      
      // Email inválido
      final resBadEmail = await cloud.requestRegister(
        name: 'Usuário Teste',
        email: 'invalid-email',
        password: 'Password123!',
      );
      expect(resBadEmail.ok, isFalse);
      expect(resBadEmail.error, contains('e-mail válido'));

      // Senha curta (< 8 chars)
      final resShortPwd = await cloud.requestRegister(
        name: 'Usuário Teste',
        email: 'test@example.com',
        password: '123',
      );
      expect(resShortPwd.ok, isFalse);
      expect(resShortPwd.error, contains('8 caracteres'));
    });

    test('confirmRegister valida código de 6 dígitos antes de enviar requisição', () async {
      final cloud = CloudSyncService.instance;

      final resEmptyCode = await cloud.confirmRegister(
        email: 'test@example.com',
        code: '',
      );
      expect(resEmptyCode.ok, isFalse);
      expect(resEmptyCode.error, contains('6 dígitos'));

      final resShortCode = await cloud.confirmRegister(
        email: 'test@example.com',
        code: '1234',
      );
      expect(resShortCode.ok, isFalse);
      expect(resShortCode.error, contains('6 dígitos'));
    });

    test('requestChangeEmail exige login ativo e rejeita mesmo e-mail', () async {
      final cloud = CloudSyncService.instance;
      cloud.logout(); // garante estado não autenticado

      final resNotAuth = await cloud.requestChangeEmail(
        password: 'password123',
        newEmail: 'novo@example.com',
      );
      expect(resNotAuth.ok, isFalse);
      expect(resNotAuth.error, contains('autenticada'));
    });

    test('confirmChangeEmail valida obrigatoriedade do código de 6 dígitos', () async {
      final cloud = CloudSyncService.instance;
      cloud.loadSessionFromConfig({
        'cloudAuthToken': 'test_token',
        'cloudUserId': 'test_user_id',
        'cloudUserEmail': 'current@example.com',
      });

      final resShort = await cloud.confirmChangeEmail(
        newEmail: 'novo@example.com',
        code: '12',
      );
      expect(resShort.ok, isFalse);
      expect(resShort.error, contains('6 dígitos'));

      cloud.logout();
    });
  });

  group('Cloud Cache Isolation & Empty Database Anti-Wipe Guardrails', () {
    test('Migra cache legado grande do sync_kv_store.json para cloud_cache/ com escrita atômica', () {
      final tempDir = Directory.systemTemp.createTempSync('om_cache_iso_');
      try {
        final legacyKv = File('${tempDir.path}/sync_kv_store.json');
        legacyKv.writeAsStringSync(jsonEncode({
          'openmoney_sync_seq_v2_u1': '42',
          'openmoney_web_cache_u1': jsonEncode({
            'revision': 42,
            'payload': {'v': 7, 'accounts': [], 'txs': []},
            'preferences': {},
          }),
        }));

        overrideNativeStorageDirForTesting(tempDir.path);
        expect(webLocalStorageGet('openmoney_sync_seq_v2_u1'), '42');
        final migratedCache = webLocalStorageGet('openmoney_web_cache_u1');
        expect(migratedCache, isNotNull);
        expect(migratedCache, contains('"revision":42'));

        final dedicatedFile = File('${tempDir.path}/cloud_cache/openmoney_web_cache_u1.json');
        expect(dedicatedFile.existsSync(), isTrue);

        // sync_kv_store.json não deve mais conter a base grande após migração
        final kvContentAfter = jsonDecode(legacyKv.readAsStringSync()) as Map;
        expect(kvContentAfter.containsKey('openmoney_web_cache_u1'), isFalse);
        expect(kvContentAfter['openmoney_sync_seq_v2_u1'], '42');
      } finally {
        overrideNativeStorageDirForTesting(null);
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('boot() rejeita cache vazio envenenado quando revision > 1 e força full pull', () {
      final tempDir = Directory.systemTemp.createTempSync('om_poison_boot_');
      try {
        overrideNativeStorageDirForTesting(tempDir.path);

        final configFile = File('${tempDir.path}/config.json');
        configFile.writeAsStringSync(jsonEncode({
          'storageMode': 'cloud',
          'dbPath': 'cloud://user@example.com',
          'cloudAuthToken': 'token_test',
          'cloudUserId': 'u_poison',
          'cloudUserEmail': 'user@example.com',
          'cloudRevision': 500,
        }));

        // Simula cache corrompido/envenenado: 0 lançamentos + conta padrão a1 na revisão 500
        webLocalStorageSet('openmoney_sync_seq_v2_u_poison', '500');
        webLocalStorageSet(
          'openmoney_web_cache_u_poison',
          jsonEncode({
            'revision': 500,
            'payload': {
              'v': 7,
              'accounts': [{'id': 'a1', 'name': 'Conta Corrente', 'type': 'Corrente', 'opening': 0}],
              'cats': [],
              'txs': [],
            },
            'preferences': {},
          }),
        );

        final store = MoneyStore(autoBoot: false, appSupportDirOverride: tempDir.path);
        store.boot();

        // Cache envenenado deve ser descartado e SyncEngine obrigado a fazer full pull
        expect(SyncEngine.instance.hasLoadedRemoteState, isFalse);
        expect(SyncEngine.instance.lastSeq, 0);
        expect(webLocalStorageGet('openmoney_web_cache_u_poison'), isNull);
        expect(store.isCloudMode, isTrue);
      } finally {
        SyncEngine.instance.stop();
        CloudSyncService.instance.logout();
        overrideNativeStorageDirForTesting(null);
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('SyncEngine.onLocalSave e CloudSyncService.pushDatabase bloqueiam base vazia quando revision > 1', () async {
      final tempDir = Directory.systemTemp.createTempSync('om_antiwipe_sync_');
      try {
        overrideNativeStorageDirForTesting(tempDir.path);
        final cloud = CloudSyncService.instance;
        cloud.loadSessionFromConfig({
          'cloudAuthToken': 'token_test',
          'cloudUserId': 'u_antiwipe',
          'cloudUserEmail': 'antiwipe@example.com',
          'cloudRevision': 250,
        });

        final store = MoneyStore(autoBoot: false, appSupportDirOverride: tempDir.path);
        final emptyDb = Database(
          accounts: [Account(id: 'a1', name: 'Conta Corrente', type: 'Corrente', opening: 0)],
          cats: List<CategoryItem>.from(kDefaultCats),
          txs: [],
          recs: [],
          budgets: {},
          v: 7,
        );

        SyncEngine.instance.configureStateForTesting(
          store: store,
          lastSeq: 250,
          hasLoadedRemoteState: true,
          baseline: {'txs/tx1': '{"id":"tx1"}', 'accounts/a1': '{}'},
        );

        SyncEngine.instance.onLocalSave(emptyDb, {});
        expect(SyncEngine.instance.pendingOutboxCount, 0);

        final pushed = await cloud.pushDatabase(
          payload: emptyDb.toJson(),
          preferences: {},
          force: false,
          compactSeq: 250,
        );
        expect(pushed, isFalse);
      } finally {
        SyncEngine.instance.stop();
        CloudSyncService.instance.logout();
        overrideNativeStorageDirForTesting(null);
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('disconnectLocalDatabase() interrompe SyncEngine e mantém isCloudMode falso mesmo autenticado', () {
      final tempDir = Directory.systemTemp.createTempSync('om_disc_');
      try {
        overrideNativeStorageDirForTesting(tempDir.path);
        final cloud = CloudSyncService.instance;
        cloud.loadSessionFromConfig({
          'cloudAuthToken': 'token_test',
          'cloudUserId': 'u_disc',
          'cloudUserEmail': 'disc@example.com',
          'cloudRevision': 10,
        });

        final store = MoneyStore(autoBoot: false, appSupportDirOverride: tempDir.path);
        SyncEngine.instance.configureStateForTesting(
          store: store,
          lastSeq: 10,
          hasLoadedRemoteState: true,
        );

        store.disconnectLocalDatabase();

        expect(store.showWelcomeScreen, isTrue);
        expect(store.isCloudMode, isFalse);
        expect(SyncEngine.instance.hasLoadedRemoteState, isFalse);
        expect(SyncEngine.instance.lastSeq, 0);
      } finally {
        SyncEngine.instance.stop();
        CloudSyncService.instance.logout();
        overrideNativeStorageDirForTesting(null);
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('ensureDailyBackup gera de 3 a 4 backups por dia na abertura e respeita turnos e intervalo mínimo', () async {
      final tempDir = Directory.systemTemp.createTempSync('om_multi_bkp_');
      try {
        final dbFile = File('${tempDir.path}/openmoney.json');
        final payload = jsonEncode({
          'v': 7,
          'accounts': [{'id': 'a1', 'name': 'Conta', 'type': 'Corrente', 'opening': 1000}],
          'cats': kDefaultCats.map((c) => c.toJson()).toList(),
          'txs': [{'id': 'tx1', 'acc': 'a1', 'date': '2026-11-17', 'amt': -500, 'payee': 'Padaria', 'cat': 'Alimentação'}],
        });
        dbFile.writeAsStringSync(payload);

        // 1. Abertura às 08:00 (Turno 1: Manhã) -> cria 1º backup
        await BackupManager.instance.ensureDailyBackup(
          appSupportDirPath: tempDir.path,
          databasePath: dbFile.path,
          nowOverride: DateTime(2026, 11, 17, 8, 0),
        );
        expect(BackupManager.instance.availableBackups(appSupportDirPath: tempDir.path).length, 1);

        // 2. Nova verificação às 08:20 (mesmo turno, < 3h) -> NÃO cria backup duplicado
        await BackupManager.instance.ensureDailyBackup(
          appSupportDirPath: tempDir.path,
          databasePath: dbFile.path,
          nowOverride: DateTime(2026, 11, 17, 8, 20),
        );
        expect(BackupManager.instance.availableBackups(appSupportDirPath: tempDir.path).length, 1);

        // 3. Abertura às 12:30 (Turno 2: Tarde, mudou turno e >= 30min / >= 3h) -> cria 2º backup
        await BackupManager.instance.ensureDailyBackup(
          appSupportDirPath: tempDir.path,
          databasePath: dbFile.path,
          nowOverride: DateTime(2026, 11, 17, 12, 30),
        );
        expect(BackupManager.instance.availableBackups(appSupportDirPath: tempDir.path).length, 2);

        // 4. Uso contínuo às 16:00 (mesmo turno, >= 3h30 desde 12:30) -> cria 3º backup
        await BackupManager.instance.ensureDailyBackup(
          appSupportDirPath: tempDir.path,
          databasePath: dbFile.path,
          nowOverride: DateTime(2026, 11, 17, 16, 0),
        );
        expect(BackupManager.instance.availableBackups(appSupportDirPath: tempDir.path).length, 3);

        // 5. Abertura às 20:00 (Turno 3: Noite, >= 3h e mudou turno) -> cria 4º backup
        await BackupManager.instance.ensureDailyBackup(
          appSupportDirPath: tempDir.path,
          databasePath: dbFile.path,
          nowOverride: DateTime(2026, 11, 17, 20, 0),
        );
        expect(BackupManager.instance.availableBackups(appSupportDirPath: tempDir.path).length, 4);

        // 6. Abertura às 23:30 (já atingiu teto de 4 backups no dia) -> mantém 4 backups
        await BackupManager.instance.ensureDailyBackup(
          appSupportDirPath: tempDir.path,
          databasePath: dbFile.path,
          nowOverride: DateTime(2026, 11, 17, 23, 30),
        );
        final all = BackupManager.instance.availableBackups(appSupportDirPath: tempDir.path);
        expect(all.length, 4);
        expect(all.map((b) => b.filename).toSet(), {
          'openmoney-backup-2026-11-17_0800.zip',
          'openmoney-backup-2026-11-17_1230.zip',
          'openmoney-backup-2026-11-17_1600.zip',
          'openmoney-backup-2026-11-17_2000.zip',
        });
      } finally {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });
  });
}

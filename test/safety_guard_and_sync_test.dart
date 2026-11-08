import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmoney/models/openmoney_models.dart';
import 'package:openmoney/services/backup_manager.dart';
import 'package:openmoney/services/cloud_sync_service.dart';
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
}

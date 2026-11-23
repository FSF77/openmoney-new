import 'package:flutter_test/flutter_test.dart';
import 'package:openmoney/services/biometric_service.dart';
import 'package:openmoney/store/money_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Biometric Unlock & Settings Tests', () {
    test('Default value of requireBiometricUnlock is false', () {
      final store = MoneyStore(autoBoot: false);
      expect(store.requireBiometricUnlock, isFalse);
    });

    test('exportPreferencesMap and applyPreferencesMap correctly handle requireBiometricUnlock', () {
      final store = MoneyStore(autoBoot: false);

      // Default export
      final prefsDefault = store.exportPreferencesMap();
      expect(prefsDefault['requireBiometricUnlock'], isFalse);

      // Apply true
      store.applyPreferencesMap({'requireBiometricUnlock': true});
      expect(store.requireBiometricUnlock, isTrue);

      final prefsTrue = store.exportPreferencesMap();
      expect(prefsTrue['requireBiometricUnlock'], isTrue);

      // Apply false
      store.applyPreferencesMap({'requireBiometricUnlock': false});
      expect(store.requireBiometricUnlock, isFalse);
    });

    test('setRequireBiometricUnlock toggles value and notifies listeners', () {
      final store = MoneyStore(autoBoot: false);
      var notified = false;
      store.addListener(() {
        notified = true;
      });

      expect(store.requireBiometricUnlock, isFalse);

      store.setRequireBiometricUnlock(true);
      expect(store.requireBiometricUnlock, isTrue);
      expect(notified, isTrue);

      notified = false;
      store.setRequireBiometricUnlock(false);
      expect(store.requireBiometricUnlock, isFalse);
      expect(notified, isTrue);
    });

    test('BiometricService state management (markUnlocked, lock, systemBiometricLabel)', () {
      final bio = BiometricService.instance;

      expect(bio.systemBiometricLabel, isNotEmpty);

      bio.markUnlocked();
      expect(bio.isUnlocked, isTrue);

      bio.lock();
      expect(bio.isUnlocked, isFalse);
    });
  });
}

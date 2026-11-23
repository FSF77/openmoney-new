import 'package:flutter_test/flutter_test.dart';
import 'package:openmoney/services/passkey_auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PasskeyAuthService Tests', () {
    test('Singleton exists with clean initial state', () {
      final service = PasskeyAuthService.instance;
      expect(service.isLoading, isFalse);
      expect(service.statusMessage, isNull);
    });

    test('isWebPasskeySupported returns boolean without crashing', () {
      final service = PasskeyAuthService.instance;
      // In native test environment, should be false
      expect(service.isWebPasskeySupported, isFalse);
    });

    test('registerPasskey on native returns informative error about web requirement', () async {
      final service = PasskeyAuthService.instance;
      final res = await service.registerPasskey(deviceName: 'Test Mac');
      expect(res.ok, isFalse);
      expect(res.error, contains('Web'));
    });
  });
}

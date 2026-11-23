import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

class BiometricService extends ChangeNotifier {
  BiometricService._();
  static final BiometricService instance = BiometricService._();

  final LocalAuthentication _auth = LocalAuthentication();

  bool _isUnlocked = false;
  bool get isUnlocked => _isUnlocked;

  bool _isAuthenticating = false;
  bool get isAuthenticating => _isAuthenticating;

  /// Retorna se a plataforma atual tem suporte a biometria nativa
  bool get isPlatformSupported => !kIsWeb;

  /// Retorna o rótulo humanizado da biometria de acordo com o sistema operacional
  String get systemBiometricLabel {
    if (kIsWeb) return 'Chave de Acesso / Biometria';
    try {
      if (Platform.isMacOS) return 'Touch ID / Senha do Mac';
      if (Platform.isIOS) return 'Face ID / Touch ID';
      if (Platform.isWindows) return 'Windows Hello';
      if (Platform.isAndroid) return 'Biometria / Impressão Digital';
    } catch (_) {}
    return 'Chave-senha / Biometria';
  }

  /// Verifica se o dispositivo possui hardware biométrico configurado e ativo
  Future<bool> canAuthenticate() async {
    if (kIsWeb) return false;
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      return canCheck || isSupported;
    } catch (e) {
      debugPrint('[BiometricService] canAuthenticate error: $e');
      return false;
    }
  }

  /// Retorna os tipos de biometria cadastrados no aparelho
  Future<List<BiometricType>> getAvailableBiometrics() async {
    if (kIsWeb) return const [];
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return const [];
    }
  }

  /// Executa o prompt nativo de autenticação biométrica
  Future<bool> authenticate({
    String reason = 'Confirme sua identidade para acessar suas finanças no OpenMoney',
  }) async {
    if (kIsWeb) {
      _isUnlocked = true;
      notifyListeners();
      return true;
    }

    if (_isAuthenticating) return false;
    _isAuthenticating = true;
    notifyListeners();

    try {
      final authenticated = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
          useErrorDialogs: true,
        ),
      );

      if (authenticated) {
        _isUnlocked = true;
      }
      return authenticated;
    } catch (e) {
      debugPrint('[BiometricService] authenticate error: $e');
      return false;
    } finally {
      _isAuthenticating = false;
      notifyListeners();
    }
  }

  /// Marca a sessão como desbloqueada
  void markUnlocked() {
    _isUnlocked = true;
    notifyListeners();
  }

  /// Bloqueia o aplicativo (exigirá nova biometria se o parâmetro estiver ativo)
  void lock() {
    _isUnlocked = false;
    notifyListeners();
  }
}

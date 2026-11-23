import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'cloud_sync_service.dart';
import 'platform_io.dart';

class PasskeyAuthService extends ChangeNotifier {
  PasskeyAuthService._();
  static final PasskeyAuthService instance = PasskeyAuthService._();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _statusMessage;
  String? get statusMessage => _statusMessage;

  /// Retorna se a plataforma atual suporta Passkeys diretamente
  bool get isWebPasskeySupported => kIsWeb && webPasskeyIsSupported();

  /// Executa o fluxo de registro de uma nova Chave-senha
  Future<({bool ok, String? message, String? error})> registerPasskey({
    String? deviceName,
    String? customApiUrl,
  }) async {
    if (!kIsWeb) {
      return (
        ok: false,
        message: null,
        error:
            'O cadastro de Chave-senha pelo navegador está disponível na versão Web.',
      );
    }
    _isLoading = true;
    _statusMessage = 'Solicitando desafio ao servidor...';
    notifyListeners();

    try {
      final opts = await CloudSyncService.instance.getPasskeyRegisterOptions(
        customApiUrl: customApiUrl,
      );
      if (opts == null) {
        return (
          ok: false,
          message: null,
          error: 'Falha ao obter desafio do servidor Cloud.',
        );
      }

      _statusMessage =
          'Aguardando autenticação biométrica (Touch ID, Windows Hello, Face ID)...';
      notifyListeners();

      final jsonResult = await webPasskeyRegister(jsonEncode(opts));
      final decoded = jsonDecode(jsonResult);
      if (decoded is! Map || decoded['ok'] != true) {
        return (
          ok: false,
          message: null,
          error: (decoded?['error'] ?? 'Autenticação cancelada').toString(),
        );
      }

      _statusMessage = 'Validando e salvando chave pública...';
      notifyListeners();

      final res = await CloudSyncService.instance.verifyPasskeyRegister(
        credentialId: decoded['credentialId'].toString(),
        clientDataJSON: decoded['clientDataJSON'].toString(),
        attestationObject: decoded['attestationObject'].toString(),
        publicKeySpki: decoded['publicKeySpki'].toString(),
        deviceName: deviceName ?? 'Este Dispositivo',
        customApiUrl: customApiUrl,
      );

      if (res.ok) {
        return (
          ok: true,
          message: res.message ?? 'Chave-senha cadastrada com sucesso!',
          error: null,
        );
      }
      return (
        ok: false,
        message: null,
        error: res.error ?? 'Falha ao salvar chave-senha.',
      );
    } catch (e) {
      return (ok: false, message: null, error: 'Erro inesperado: $e');
    } finally {
      _isLoading = false;
      _statusMessage = null;
      notifyListeners();
    }
  }

  /// Executa o login com Chave-senha
  Future<({bool ok, String? error})> loginWithPasskey({
    String? email,
    String? sessionId,
    String? customApiUrl,
  }) async {
    _isLoading = true;
    _statusMessage = 'Iniciando autenticação com Chave-senha...';
    notifyListeners();

    try {
      if (kIsWeb) {
        // Fluxo direto in-page Web
        final opts = await CloudSyncService.instance.getPasskeyLoginOptions(
          email: email,
          customApiUrl: customApiUrl,
        );
        if (opts == null) {
          return (
            ok: false,
            error: 'Falha ao obter opções de autenticação com Chave-senha.',
          );
        }

        _statusMessage =
          'Aguardando autenticação por biometria / Touch ID / Windows Hello...';
        notifyListeners();

        final jsonResult = await webPasskeyLogin(jsonEncode(opts));
        final decoded = jsonDecode(jsonResult);
        if (decoded is! Map || decoded['ok'] != true) {
          return (
            ok: false,
            error: (decoded?['error'] ?? 'Autenticação cancelada').toString(),
          );
        }

        _statusMessage = 'Validando assinatura biométrica no servidor...';
        notifyListeners();

        final res = await CloudSyncService.instance.verifyPasskeyLogin(
          credentialId: decoded['credentialId'].toString(),
          clientDataJSON: decoded['clientDataJSON'].toString(),
          authenticatorData: decoded['authenticatorData'].toString(),
          signature: decoded['signature'].toString(),
          userHandle: decoded['userHandle']?.toString(),
          sessionId: sessionId,
          customApiUrl: customApiUrl,
        );

        return (ok: res.ok, error: res.error);
      } else {
        // Fluxo Desktop (macOS, Windows, Linux) via Desktop Session Bridge
        final dSession = await CloudSyncService.instance
            .createPasskeyDesktopSession(customApiUrl: customApiUrl);
        if (dSession.sessionId == null) {
          return (
            ok: false,
            error: dSession.error ??
                'Não foi possível criar a sessão de Chave-senha no Desktop.',
          );
        }
        final dSessionId = dSession.sessionId!;

        final baseUrl = (customApiUrl != null && customApiUrl.isNotEmpty)
            ? customApiUrl
            : CloudSyncService.instance.apiBaseUrl;
        final authUrl =
            '$baseUrl/?passkey_session=$dSessionId${email != null && email.isNotEmpty ? "&email=${Uri.encodeComponent(email)}" : ""}';

        webOpenExternalUrl(authUrl);

        _statusMessage =
            'Conclua a autenticação com Chave-senha no seu navegador aberto...';
        notifyListeners();

        final completer = Completer<({bool ok, String? error})>();
        var elapsed = 0;
        Timer.periodic(const Duration(seconds: 2), (timer) async {
          elapsed += 2;
          if (elapsed > 90) {
            timer.cancel();
            if (!completer.isCompleted) {
              completer.complete((
                ok: false,
                error:
                    'Tempo limite excedido para confirmar a Chave-senha no navegador.',
              ));
            }
            return;
          }

          final status = await CloudSyncService.instance
              .checkPasskeyDesktopSession(
                sessionId: dSessionId,
                customApiUrl: customApiUrl,
              );
          if (status.ok) {
            timer.cancel();
            if (!completer.isCompleted) {
              completer.complete((ok: true, error: null));
            }
          } else if (status.error != null && status.message != 'pending') {
            timer.cancel();
            if (!completer.isCompleted) {
              completer.complete((ok: false, error: status.error));
            }
          }
        });

        return await completer.future;
      }
    } catch (e) {
      return (ok: false, error: 'Erro de autenticação: $e');
    } finally {
      _isLoading = false;
      _statusMessage = null;
      notifyListeners();
    }
  }
}

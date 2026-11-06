import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'platform_io.dart';

enum CloudSyncState {
  disconnected,
  connecting,
  synced,
  syncing,
  conflict,
  error,
}

class CloudBackupInfo {
  final String id;
  final String backupDate;
  final int revision;
  final String createdAt;
  final int sizeBytes;

  const CloudBackupInfo({
    required this.id,
    required this.backupDate,
    required this.revision,
    required this.createdAt,
    required this.sizeBytes,
  });

  factory CloudBackupInfo.fromJson(Map<String, dynamic> json) {
    return CloudBackupInfo(
      id: (json['id'] ?? '').toString(),
      backupDate: (json['backup_date'] ?? json['backupDate'] ?? '').toString(),
      revision: (json['revision'] as num?)?.toInt() ?? 1,
      createdAt: (json['created_at'] ?? json['createdAt'] ?? '').toString(),
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
    );
  }

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class CloudDatabaseSnapshot {
  final Map<String, dynamic> payload;
  final Map<String, dynamic> preferences;
  final int revision;
  final String updatedAt;

  const CloudDatabaseSnapshot({
    required this.payload,
    required this.preferences,
    required this.revision,
    required this.updatedAt,
  });
}

class CloudSyncService extends ChangeNotifier {
  CloudSyncService._();
  static final CloudSyncService instance = CloudSyncService._();

  static const String _kWebSessionKey = 'openmoney_cloud_session_v1';

  String _apiBaseUrl = '';
  String _authToken = '';
  String _userId = '';
  String _userEmail = '';
  String _userName = '';
  int _revision = 0;
  DateTime? _lastSyncedAt;
  String? _lastError;
  CloudSyncState _state = CloudSyncState.disconnected;
  bool _webOfflineGuestMode = false;
  bool _webAuthFlowInProgress = false;

  String get apiBaseUrl => _apiBaseUrl;
  String get authToken => _authToken;
  String get userId => _userId;
  String get userEmail => _userEmail;
  String get userName => _userName;
  int get revision => _revision;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  String? get lastError => _lastError;
  CloudSyncState get state => _state;
  bool get isAuthenticated => _authToken.isNotEmpty && _userId.isNotEmpty;
  bool get isWebOfflineGuestMode => _webOfflineGuestMode;
  bool get isWebAuthFlowInProgress => _webAuthFlowInProgress;

  void setWebAuthFlowInProgress(bool value) {
    if (_webAuthFlowInProgress == value) return;
    _webAuthFlowInProgress = value;
    notifyListeners();
  }

  String get resolvedBaseUrl {
    final trimmed = _apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.isNotEmpty) return trimmed;
    if (kIsWeb) {
      final origin = webWindowOrigin().trim().replaceAll(RegExp(r'/+$'), '');
      return origin;
    }
    return '';
  }

  String get statusLabel {
    if (!isAuthenticated) {
      return _webOfflineGuestMode ? 'Modo Local (Navegador)' : 'Desconectado';
    }
    switch (_state) {
      case CloudSyncState.disconnected:
        return 'Desconectado';
      case CloudSyncState.connecting:
        return 'Conectando...';
      case CloudSyncState.syncing:
        return 'Sincronizando...';
      case CloudSyncState.synced:
        return 'Sincronizado (r$_revision)';
      case CloudSyncState.conflict:
        return 'Conflito de Revisão';
      case CloudSyncState.error:
        return 'Offline / Pendente';
    }
  }

  /// Inicializa a sessão a partir da configuração salva (Desktop/Mobile ou Web localStorage)
  void loadSessionFromConfig(Map<String, dynamic> cfg) {
    Map<String, dynamic> source = cfg;
    if (kIsWeb) {
      final raw = webLocalStorageGet(_kWebSessionKey);
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            source = decoded;
          }
        } catch (_) {}
      }
    }

    _apiBaseUrl = (source['cloudApiBaseUrl'] as String?)?.trim() ?? '';
    _authToken = (source['cloudAuthToken'] as String?)?.trim() ?? '';
    _userId = (source['cloudUserId'] as String?)?.trim() ?? '';
    _userEmail = (source['cloudUserEmail'] as String?)?.trim() ?? '';
    _userName = (source['cloudUserName'] as String?)?.trim() ?? '';
    _revision = (source['cloudRevision'] as num?)?.toInt() ?? 0;
    final lastSyncStr = source['cloudLastSyncedAt'] as String?;
    if (lastSyncStr != null && lastSyncStr.isNotEmpty) {
      _lastSyncedAt = DateTime.tryParse(lastSyncStr);
    }

    if (isAuthenticated) {
      _state = CloudSyncState.synced;
    } else {
      _state = CloudSyncState.disconnected;
    }
    notifyListeners();
  }

  Map<String, dynamic> exportSessionToConfig(Map<String, dynamic> baseCfg) {
    final cfg = Map<String, dynamic>.from(baseCfg);
    cfg['cloudApiBaseUrl'] = _apiBaseUrl;
    cfg['cloudAuthToken'] = _authToken;
    cfg['cloudUserId'] = _userId;
    cfg['cloudUserEmail'] = _userEmail;
    cfg['cloudUserName'] = _userName;
    cfg['cloudRevision'] = _revision;
    if (_lastSyncedAt != null) {
      cfg['cloudLastSyncedAt'] = _lastSyncedAt!.toIso8601String();
    }
    if (kIsWeb) {
      webLocalStorageSet(_kWebSessionKey, jsonEncode(cfg));
    }
    return cfg;
  }

  void enableWebOfflineGuestMode() {
    _webOfflineGuestMode = true;
    notifyListeners();
  }

  void setApiBaseUrl(String url) {
    _apiBaseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    notifyListeners();
  }

  Map<String, String> _headers() {
    return <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      if (_authToken.isNotEmpty) 'Authorization': 'Bearer $_authToken',
    };
  }

  String _endpoint(String path) {
    final base = resolvedBaseUrl;
    if (base.isEmpty) return path;
    return '$base$path';
  }

  Future<({bool ok, String? error})> login({
    required String email,
    required String password,
    String? customApiUrl,
  }) async {
    if (customApiUrl != null) {
      _apiBaseUrl = customApiUrl.trim().replaceAll(RegExp(r'/+$'), '');
    }
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty || password.isEmpty) {
      return (ok: false, error: 'Informe seu e-mail e senha.');
    }
    if (!kIsWeb && resolvedBaseUrl.isEmpty) {
      return (
        ok: false,
        error: 'Informe a URL do seu servidor Cloudflare Pages (ex: https://openmoney.seudominio.com.br).',
      );
    }

    _state = CloudSyncState.connecting;
    _lastError = null;
    notifyListeners();

    try {
      final res = await platformHttpRequest(
        method: 'POST',
        url: _endpoint('/api/auth/login'),
        headers: _headers(),
        body: jsonEncode({
          'email': cleanEmail,
          'password': password,
        }),
      );

      final decoded = _tryDecodeJson(res.body);
      if (res.statusCode >= 200 && res.statusCode < 300 && decoded != null) {
        _authToken = (decoded['token'] ?? '').toString();
        final user = decoded['user'] as Map<String, dynamic>? ?? {};
        _userId = (user['id'] ?? '').toString();
        _userEmail = (user['email'] ?? cleanEmail).toString();
        _userName = (user['name'] ?? '').toString();
        _revision = (decoded['revision'] as num?)?.toInt() ?? 0;
        _webOfflineGuestMode = false;
        _state = CloudSyncState.synced;
        _lastError = null;
        if (kIsWeb) {
          exportSessionToConfig({});
        }
        notifyListeners();
        return (ok: true, error: null);
      }

      final errMsg = (decoded?['error'] ??
              'Falha na autenticação (HTTP ${res.statusCode}).')
          .toString();
      _state = CloudSyncState.disconnected;
      _lastError = errMsg;
      notifyListeners();
      return (ok: false, error: errMsg);
    } catch (e) {
      const msg =
          'Não foi possível conectar ao servidor Cloudflare. Verifique a URL ou sua conexão.';
      _state = CloudSyncState.error;
      _lastError = msg;
      notifyListeners();
      return (ok: false, error: msg);
    }
  }

  Future<({bool ok, String? error})> register({
    required String name,
    required String email,
    required String password,
    String? inviteCode,
    String? customApiUrl,
    Map<String, dynamic>? initialPayload,
  }) async {
    if (customApiUrl != null) {
      _apiBaseUrl = customApiUrl.trim().replaceAll(RegExp(r'/+$'), '');
    }
    final cleanEmail = email.trim().toLowerCase();
    final cleanName = name.trim();
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      return (ok: false, error: 'Informe um endereço de e-mail válido.');
    }
    if (password.length < 8) {
      return (
        ok: false,
        error: 'A senha deve ter pelo menos 8 caracteres para sua segurança.',
      );
    }
    if (!kIsWeb && resolvedBaseUrl.isEmpty) {
      return (
        ok: false,
        error: 'Informe a URL do seu servidor Cloudflare Pages.',
      );
    }

    _state = CloudSyncState.connecting;
    _lastError = null;
    notifyListeners();

    try {
      final res = await platformHttpRequest(
        method: 'POST',
        url: _endpoint('/api/auth/register'),
        headers: _headers(),
        body: jsonEncode({
          'name': cleanName,
          'email': cleanEmail,
          'password': password,
          if (inviteCode != null && inviteCode.trim().isNotEmpty)
            'inviteCode': inviteCode.trim(),
          if (initialPayload != null) 'initialPayload': initialPayload,
        }),
      );

      final decoded = _tryDecodeJson(res.body);
      if (res.statusCode >= 200 && res.statusCode < 300 && decoded != null) {
        _authToken = (decoded['token'] ?? '').toString();
        final user = decoded['user'] as Map<String, dynamic>? ?? {};
        _userId = (user['id'] ?? '').toString();
        _userEmail = (user['email'] ?? cleanEmail).toString();
        _userName = (user['name'] ?? cleanName).toString();
        _revision = (decoded['revision'] as num?)?.toInt() ?? 1;
        _webOfflineGuestMode = false;
        _state = CloudSyncState.synced;
        _lastError = null;
        if (kIsWeb) {
          exportSessionToConfig({});
        }
        notifyListeners();
        return (ok: true, error: null);
      }

      final errMsg =
          (decoded?['error'] ?? 'Erro ao criar conta (HTTP ${res.statusCode}).')
              .toString();
      _state = CloudSyncState.disconnected;
      _lastError = errMsg;
      notifyListeners();
      return (ok: false, error: errMsg);
    } catch (e) {
      const msg =
          'Não foi possível conectar ao servidor Cloudflare. Verifique a URL ou sua conexão.';
      _state = CloudSyncState.error;
      _lastError = msg;
      notifyListeners();
      return (ok: false, error: msg);
    }
  }

  Future<({bool ok, String? error})> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (!isAuthenticated) {
      return (ok: false, error: 'Sessão não autenticada.');
    }
    if (newPassword.length < 8) {
      return (ok: false, error: 'A nova senha deve ter no mínimo 8 caracteres.');
    }
    try {
      final res = await platformHttpRequest(
        method: 'POST',
        url: _endpoint('/api/auth/change-password'),
        headers: _headers(),
        body: jsonEncode({
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        }),
      );
      final decoded = _tryDecodeJson(res.body);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return (ok: true, error: null);
      }
      return (
        ok: false,
        error: (decoded?['error'] ?? 'Falha ao alterar senha.').toString(),
      );
    } catch (_) {
      return (ok: false, error: 'Erro de conexão ao alterar senha.');
    }
  }

  void logout() {
    _authToken = '';
    _userId = '';
    _userEmail = '';
    _userName = '';
    _revision = 0;
    _lastSyncedAt = null;
    _lastError = null;
    _webOfflineGuestMode = false;
    _state = CloudSyncState.disconnected;
    if (kIsWeb) {
      webLocalStorageRemove(_kWebSessionKey);
    }
    notifyListeners();
  }

  /// Baixa o openmoney.json (Schema v7) exclusivo do usuário autenticado via stream binário Gzip
  Future<CloudDatabaseSnapshot?> fetchDatabase() async {
    if (!isAuthenticated) return null;

    _state = CloudSyncState.syncing;
    notifyListeners();

    try {
      final res = await platformHttpBinaryRequest(
        method: 'GET',
        url: _endpoint('/api/db?format=binary'),
        headers: {
          'Authorization': 'Bearer $_authToken',
          'Accept': 'application/octet-stream, application/json',
        },
      );

      if (res.statusCode == 401) {
        logout();
        return null;
      }

      final contentType = (res.headers['content-type'] ?? '').toLowerCase();

      if (res.statusCode >= 200 &&
          res.statusCode < 300 &&
          contentType.contains('application/octet-stream')) {
        // Descomprime Gzip localmente no cliente (suporta bases de 12MB+ sem estourar CPU do Worker)
        final isGzip =
            (res.headers['x-openmoney-compression'] ?? '').toLowerCase() ==
                'gzip';
        final rawBytes = isGzip
            ? await platformGzipDecompress(res.bodyBytes)
            : res.bodyBytes;
        final rawJson = utf8.decode(rawBytes, allowMalformed: true);
        final payloadMap = _tryDecodeJson(rawJson) ?? <String, dynamic>{};

        Map<String, dynamic> prefsMap = {};
        final prefsB64 = res.headers['x-openmoney-prefs'] ?? '';
        if (prefsB64.isNotEmpty) {
          try {
            String normalized = prefsB64.replaceAll('-', '+').replaceAll('_', '/');
            while (normalized.length % 4 != 0) {
              normalized += '=';
            }
            final prefsStr =
                utf8.decode(base64.decode(normalized), allowMalformed: true);
            prefsMap = _tryDecodeJson(prefsStr) ?? {};
          } catch (_) {}
        }

        final rev =
            int.tryParse(res.headers['x-openmoney-revision'] ?? '') ?? 1;
        final updatedAt = res.headers['x-openmoney-updated-at'] ?? '';

        _revision = rev;
        _lastSyncedAt = DateTime.now();
        _state = CloudSyncState.synced;
        _lastError = null;

        if (kIsWeb && _userId.isNotEmpty && payloadMap.isNotEmpty) {
          if (rawJson.length < 2000000) {
            webLocalStorageSet(
              'openmoney_web_cache_$_userId',
              jsonEncode({
                'revision': _revision,
                'payload': payloadMap,
                'preferences': prefsMap,
              }),
            );
          } else {
            // Bases >2MB excedem a cota de 5MB do localStorage do navegador; mantemos apenas na nuvem/memória
            webLocalStorageRemove('openmoney_web_cache_$_userId');
          }
          exportSessionToConfig({});
        }

        notifyListeners();
        return CloudDatabaseSnapshot(
          payload: payloadMap,
          preferences: prefsMap,
          revision: rev,
          updatedAt: updatedAt,
        );
      }

      final bodyText = utf8.decode(res.bodyBytes, allowMalformed: true);
      final decoded = _tryDecodeJson(bodyText);
      if (res.statusCode >= 200 && res.statusCode < 300 && decoded != null) {
        final rawPayload = decoded['payload'];
        Map<String, dynamic> payloadMap = {};
        if (rawPayload is Map<String, dynamic>) {
          payloadMap = rawPayload;
        } else if (rawPayload is String && rawPayload.isNotEmpty) {
          final p = _tryDecodeJson(rawPayload);
          if (p != null) payloadMap = p;
        }

        final rawPrefs = decoded['preferences'];
        Map<String, dynamic> prefsMap = {};
        if (rawPrefs is Map<String, dynamic>) {
          prefsMap = rawPrefs;
        } else if (rawPrefs is String && rawPrefs.isNotEmpty) {
          final pr = _tryDecodeJson(rawPrefs);
          if (pr != null) prefsMap = pr;
        }

        final rev = (decoded['revision'] as num?)?.toInt() ?? 1;
        final updatedAt = (decoded['updatedAt'] ?? '').toString();

        _revision = rev;
        _lastSyncedAt = DateTime.now();
        _state = CloudSyncState.synced;
        _lastError = null;

        if (kIsWeb && _userId.isNotEmpty) {
          exportSessionToConfig({});
        }

        notifyListeners();
        return CloudDatabaseSnapshot(
          payload: payloadMap,
          preferences: prefsMap,
          revision: rev,
          updatedAt: updatedAt,
        );
      }

      _state = CloudSyncState.error;
      _lastError =
          (decoded?['error'] ?? 'Erro HTTP ${res.statusCode}').toString();
      notifyListeners();
    } catch (e) {
      _state = CloudSyncState.error;
      _lastError = 'Sem conexão com a nuvem no momento.';
      notifyListeners();
    }

    // Fallback para o cache local do próprio usuário na Web se estiver sem rede
    if (kIsWeb && _userId.isNotEmpty) {
      final cachedRaw = webLocalStorageGet('openmoney_web_cache_$_userId');
      if (cachedRaw != null && cachedRaw.isNotEmpty) {
        final cached = _tryDecodeJson(cachedRaw);
        if (cached != null && cached['payload'] is Map<String, dynamic>) {
          return CloudDatabaseSnapshot(
            payload: cached['payload'] as Map<String, dynamic>,
            preferences:
                (cached['preferences'] as Map<String, dynamic>?) ?? const {},
            revision: (cached['revision'] as num?)?.toInt() ?? _revision,
            updatedAt: '',
          );
        }
      }
    }

    return null;
  }

  /// Envia o openmoney.json (Schema v7) pré-comprimido em Gzip para a nuvem
  Future<bool> pushDatabase({
    required Map<String, dynamic> payload,
    required Map<String, dynamic> preferences,
    bool force = false,
  }) async {
    final rawJson = jsonEncode(payload);

    if (kIsWeb && _userId.isNotEmpty) {
      if (rawJson.length < 2000000) {
        webLocalStorageSet(
          'openmoney_web_cache_$_userId',
          jsonEncode({
            'revision': _revision,
            'payload': payload,
            'preferences': preferences,
          }),
        );
      } else {
        webLocalStorageRemove('openmoney_web_cache_$_userId');
      }
    } else if (kIsWeb && _webOfflineGuestMode) {
      if (rawJson.length < 2000000) {
        webLocalStorageSet(
          'openmoney_web_guest_db',
          jsonEncode({
            'payload': payload,
            'preferences': preferences,
          }),
        );
      }
      return true;
    }

    if (!isAuthenticated) return false;

    _state = CloudSyncState.syncing;
    notifyListeners();

    try {
      final rawBytes = Uint8List.fromList(utf8.encode(rawJson));
      final compressedBytes = await platformGzipCompress(rawBytes);
      final prefsB64 = base64Url
          .encode(utf8.encode(jsonEncode(preferences)))
          .replaceAll('=', '');

      final res = await platformHttpBinaryRequest(
        method: 'PUT',
        url: _endpoint('/api/db'),
        headers: {
          'Authorization': 'Bearer $_authToken',
          'Content-Type': 'application/octet-stream',
          'X-OpenMoney-Compression': 'gzip',
          'X-OpenMoney-Raw-Size': '${rawBytes.length}',
          'X-OpenMoney-Prefs': prefsB64,
        },
        bodyBytes: compressedBytes,
      );

      if (res.statusCode == 401) {
        logout();
        return false;
      }

      final bodyText = utf8.decode(res.bodyBytes, allowMalformed: true);
      final decoded = _tryDecodeJson(bodyText);
      if (res.statusCode == 409) {
        _state = CloudSyncState.conflict;
        _lastError =
            'Existe uma versão mais recente na nuvem. Sincronize antes de sobrescrever.';
        notifyListeners();
        return false;
      }

      if (res.statusCode >= 200 && res.statusCode < 300 && decoded != null) {
        _revision = (decoded['revision'] as num?)?.toInt() ?? (_revision + 1);
        _lastSyncedAt = DateTime.now();
        _state = CloudSyncState.synced;
        _lastError = null;
        if (kIsWeb) {
          exportSessionToConfig({});
        }
        notifyListeners();
        return true;
      }

      _state = CloudSyncState.error;
      _lastError =
          (decoded?['error'] ?? 'Falha ao salvar na nuvem (${res.statusCode})')
              .toString();
      notifyListeners();
      return false;
    } catch (e) {
      _state = CloudSyncState.error;
      _lastError = 'Alterações salvas localmente (aguardando conexão).';
      notifyListeners();
      return false;
    }
  }

  /// Lista os backups diários automáticos armazenados na nuvem para este usuário
  Future<List<CloudBackupInfo>> listCloudBackups() async {
    if (!isAuthenticated) return const [];
    try {
      final res = await platformHttpRequest(
        method: 'GET',
        url: _endpoint('/api/backups'),
        headers: _headers(),
      );
      final decoded = _tryDecodeJson(res.body);
      if (res.statusCode >= 200 &&
          res.statusCode < 300 &&
          decoded != null &&
          decoded['backups'] is List) {
        return (decoded['backups'] as List)
            .whereType<Map>()
            .map((m) => CloudBackupInfo.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  /// Restaura um backup diário específico da nuvem para a conta do usuário
  Future<CloudDatabaseSnapshot?> restoreCloudBackup(String backupId) async {
    if (!isAuthenticated || backupId.isEmpty) return null;
    try {
      final res = await platformHttpRequest(
        method: 'POST',
        url: _endpoint('/api/backups/restore'),
        headers: _headers(),
        body: jsonEncode({'backupId': backupId}),
      );
      final decoded = _tryDecodeJson(res.body);
      if (res.statusCode >= 200 && res.statusCode < 300 && decoded != null) {
        return await fetchDatabase();
      }
    } catch (_) {}
    return null;
  }

  Map<String, dynamic>? _tryDecodeJson(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }
}

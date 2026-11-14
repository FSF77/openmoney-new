import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../models/openmoney_models.dart';
import '../store/money_store.dart';
import 'backup_manager.dart';
import 'cloud_sync_service.dart';
import 'platform_io.dart';

class SyncChange {
  final String coll;
  final String id;
  final dynamic data;
  final bool deleted;
  final int seq;

  const SyncChange({
    required this.coll,
    required this.id,
    this.data,
    this.deleted = false,
    this.seq = 0,
  });

  Map<String, dynamic> toJson() => {
        'coll': coll,
        'id': id,
        'data': deleted ? null : data,
        if (deleted) 'deleted': true,
        if (seq > 0) 'seq': seq,
      };

  factory SyncChange.fromJson(Map<String, dynamic> json) {
    final isDel = json['deleted'] == true || json['data'] == null;
    return SyncChange(
      coll: (json['coll'] ?? '').toString(),
      id: (json['id'] ?? '').toString(),
      data: isDel ? null : json['data'],
      deleted: isDel,
      seq: (json['seq'] as num?)?.toInt() ?? 0,
    );
  }
}

class SyncEngine extends ChangeNotifier with WidgetsBindingObserver {
  SyncEngine._();
  static final SyncEngine instance = SyncEngine._();

  MoneyStore? _store;
  final Map<String, String> _baseline = <String, String>{};
  final Map<String, SyncChange> _outbox = <String, SyncChange>{};

  int _lastSeq = 0;
  bool _hasLoadedRemoteState = false;
  bool _isRunning = false;
  bool _isSyncing = false;
  bool _isApplyingRemote = false;
  bool _pendingForceFullPull = false;
  Future<bool>? _activeSyncFuture;
  bool _wsConnected = false;
  int _wsFailCount = 0;
  DateTime? _nextWsAttemptAt;

  Timer? _deltaPollTimer;
  Timer? _wsPingTimer;
  Timer? _flushTimer;
  Timer? _compactTimer;
  PlatformWebSocket? _ws;

  int get lastSeq => _lastSeq;
  bool get hasLoadedRemoteState => _hasLoadedRemoteState;
  int get pendingOutboxCount => _outbox.length;
  bool get isSyncing => _isSyncing;
  bool get isWsConnected => _wsConnected;
  bool get isApplyingRemote => _isApplyingRemote;

  String _seqStorageKey(String userId) => 'openmoney_sync_seq_v2_$userId';
  String _outboxStorageKey(String userId) => 'openmoney_sync_outbox_v2_$userId';
  String _cacheStorageKey(String userId) => 'openmoney_web_cache_$userId';

  // ==========================================================================
  // Extração Granular, Diff e Merge por Registro (Testáveis e Determinísticos)
  // ==========================================================================

  static Map<String, ({String coll, String id, dynamic data, String jsonStr})>
      extractRecordMap(Database db, Map<String, dynamic> prefs) {
    final map =
        <String, ({String coll, String id, dynamic data, String jsonStr})>{};

    for (final acc in db.accounts) {
      final d = acc.toJson();
      map['accounts/${acc.id}'] = (
        coll: 'accounts',
        id: acc.id,
        data: d,
        jsonStr: jsonEncode(d),
      );
    }

    for (final cat in db.cats) {
      final cid = cat.id;
      final d = cat.toJson();
      map['cats/$cid'] = (
        coll: 'cats',
        id: cid,
        data: d,
        jsonStr: jsonEncode(d),
      );
    }

    for (final tx in db.txs) {
      final d = tx.toJson();
      map['txs/${tx.id}'] = (
        coll: 'txs',
        id: tx.id,
        data: d,
        jsonStr: jsonEncode(d),
      );
    }

    for (final rec in db.recs) {
      final d = rec.toJson();
      map['recs/${rec.id}'] = (
        coll: 'recs',
        id: rec.id,
        data: d,
        jsonStr: jsonEncode(d),
      );
    }

    db.budgets.forEach((k, v) {
      map['budgets/$k'] = (
        coll: 'budgets',
        id: k,
        data: v,
        jsonStr: jsonEncode(v),
      );
    });

    db.comments.forEach((k, v) {
      map['comments/$k'] = (
        coll: 'comments',
        id: k,
        data: v,
        jsonStr: jsonEncode(v),
      );
    });

    for (final tag in db.tags) {
      map['tags/$tag'] = (
        coll: 'tags',
        id: tag,
        data: tag,
        jsonStr: jsonEncode(tag),
      );
    }

    map['meta/predMode'] = (
      coll: 'meta',
      id: 'predMode',
      data: db.predMode,
      jsonStr: jsonEncode(db.predMode),
    );

    final accOrder = db.accounts.map((a) => a.id).toList();
    map['meta/accountOrder'] = (
      coll: 'meta',
      id: 'accountOrder',
      data: accOrder,
      jsonStr: jsonEncode(accOrder),
    );

    if (prefs.isNotEmpty) {
      map['prefs/userPrefs'] = (
        coll: 'prefs',
        id: 'userPrefs',
        data: prefs,
        jsonStr: jsonEncode(prefs),
      );
    }

    return map;
  }

  static List<SyncChange> computeDiff({
    required Map<String, String> baseline,
    required Database db,
    required Map<String, dynamic> prefs,
  }) {
    final current = extractRecordMap(db, prefs);
    final changes = <SyncChange>[];

    // 1. Novos registros ou registros modificados
    current.forEach((key, entry) {
      final prevJson = baseline[key];
      if (prevJson != entry.jsonStr) {
        changes.add(
          SyncChange(
            coll: entry.coll,
            id: entry.id,
            data: entry.data,
            deleted: false,
          ),
        );
        baseline[key] = entry.jsonStr;
      }
    });

    // 2. Registros excluídos (Tombstones)
    final removedKeys = <String>[];
    for (final oldKey in baseline.keys) {
      if (!current.containsKey(oldKey)) {
        removedKeys.add(oldKey);
      }
    }
    for (final oldKey in removedKeys) {
      baseline.remove(oldKey);
      final slashIdx = oldKey.indexOf('/');
      if (slashIdx <= 0) continue;
      final coll = oldKey.substring(0, slashIdx);
      final id = oldKey.substring(slashIdx + 1);
      changes.add(
        SyncChange(
          coll: coll,
          id: id,
          data: null,
          deleted: true,
        ),
      );
    }

    return changes;
  }

  static bool applyChangesToDatabase({
    required Database db,
    required Map<String, dynamic> prefs,
    required List<SyncChange> changes,
    required Map<String, String> baseline,
  }) {
    if (changes.isEmpty) return false;
    bool modified = false;

    Map<String, Account>? accMap;
    Map<String, CategoryItem>? catMap;
    Map<String, Transaction>? txMap;
    Map<String, RecurrenceRule>? recMap;
    List<String>? pendingAccountOrder;

    for (final ch in changes) {
      final coll = ch.coll;
      final id = ch.id;
      if (coll.isEmpty || id.isEmpty) continue;
      final key = '$coll/$id';
      final isDel = ch.deleted || ch.data == null;

      if (coll == 'txs') {
        txMap ??= {for (final t in db.txs) t.id: t};
        if (isDel) {
          if (txMap.remove(id) != null) modified = true;
          baseline.remove(key);
        } else if (ch.data is Map) {
          final parsed =
              Transaction.fromJson(Map<String, dynamic>.from(ch.data as Map));
          txMap[id] = parsed;
          baseline[key] = jsonEncode(parsed.toJson());
          modified = true;
        }
      } else if (coll == 'accounts') {
        accMap ??= {for (final a in db.accounts) a.id: a};
        if (isDel) {
          if (accMap.remove(id) != null) modified = true;
          baseline.remove(key);
        } else if (ch.data is Map) {
          final parsed =
              Account.fromJson(Map<String, dynamic>.from(ch.data as Map));
          accMap[id] = parsed;
          baseline[key] = jsonEncode(parsed.toJson());
          modified = true;
        }
      } else if (coll == 'cats') {
        catMap ??= {for (final c in db.cats) c.id: c};
        if (isDel) {
          if (catMap.remove(id) != null) modified = true;
          baseline.remove(key);
        } else {
          final parsed = CategoryItem.fromJson(ch.data);
          catMap[parsed.id] = parsed;
          baseline['cats/${parsed.id}'] = jsonEncode(parsed.toJson());
          modified = true;
        }
      } else if (coll == 'recs') {
        recMap ??= {for (final r in db.recs) r.id: r};
        if (isDel) {
          if (recMap.remove(id) != null) modified = true;
          baseline.remove(key);
        } else if (ch.data is Map) {
          final parsed = RecurrenceRule.fromJson(
              Map<String, dynamic>.from(ch.data as Map));
          recMap[id] = parsed;
          baseline[key] = jsonEncode(parsed.toJson());
          modified = true;
        }
      } else if (coll == 'budgets') {
        if (isDel) {
          if (db.budgets.remove(id) != null) modified = true;
          baseline.remove(key);
        } else if (ch.data is num) {
          final val = (ch.data as num).toInt();
          db.budgets[id] = val;
          baseline[key] = jsonEncode(val);
          modified = true;
        }
      } else if (coll == 'comments') {
        if (isDel) {
          if (db.comments.remove(id) != null) modified = true;
          baseline.remove(key);
        } else if (ch.data != null) {
          final val = ch.data.toString();
          db.comments[id] = val;
          baseline[key] = jsonEncode(val);
          modified = true;
        }
      } else if (coll == 'tags') {
        if (isDel) {
          final prevLen = db.tags.length;
          db.tags.removeWhere((t) => t.toLowerCase() == id.toLowerCase());
          if (db.tags.length != prevLen) modified = true;
          baseline.remove(key);
        } else {
          final tagName = (ch.data?.toString() ?? id).trim();
          if (tagName.isNotEmpty) {
            if (!db.tags.any((t) => t.toLowerCase() == tagName.toLowerCase())) {
              db.tags.add(tagName);
              db.tags.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
              modified = true;
            }
            baseline[key] = jsonEncode(tagName);
          }
        }
      } else if (coll == 'meta') {
        if (id == 'predMode' && !isDel) {
          final mode = ch.data == 'invoice' ? 'invoice' : 'month';
          if (db.predMode != mode) {
            db.predMode = mode;
            modified = true;
          }
          baseline[key] = jsonEncode(mode);
        } else if (id == 'accountOrder' && ch.data is List) {
          pendingAccountOrder =
              (ch.data as List).map((e) => e.toString()).toList();
          baseline[key] = jsonEncode(pendingAccountOrder);
          modified = true;
        }
      } else if (coll == 'prefs') {
        if (id == 'userPrefs' && ch.data is Map) {
          final incomingPrefs = Map<String, dynamic>.from(ch.data as Map);
          prefs.addAll(incomingPrefs);
          baseline[key] = jsonEncode(prefs);
          modified = true;
        }
      }
    }

    if (txMap != null) db.txs = txMap.values.toList();
    if (accMap != null) {
      final list = accMap.values.toList();
      if (list.isNotEmpty) {
        db.accounts = list;
      }
    }
    if (catMap != null) db.cats = catMap.values.toList();
    if (recMap != null) db.recs = recMap.values.toList();

    if (pendingAccountOrder != null && db.accounts.length > 1) {
      final byId = {for (final a in db.accounts) a.id: a};
      final ordered = <Account>[];
      for (final aid in pendingAccountOrder) {
        final acc = byId.remove(aid);
        if (acc != null) ordered.add(acc);
      }
      ordered.addAll(byId.values);
      db.accounts = ordered;
    }

    return modified;
  }

  // ==========================================================================
  // Inicialização e Ciclo de Vida (Apenas Web na Etapa 1)
  // ==========================================================================

  void seedBaseline(Database db, Map<String, dynamic> prefs) {
    _baseline.clear();
    final current = extractRecordMap(db, prefs);
    current.forEach((key, entry) {
      _baseline[key] = entry.jsonStr;
    });
  }

  void start(
    MoneyStore store, {
    bool triggerInitialSync = true,
    bool hasValidLocalCache = false,
  }) {
    _store = store;
    final cloud = CloudSyncService.instance;
    if (!cloud.isAuthenticated) {
      stop();
      return;
    }

    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}

    _loadPersistedState(
      cloud.userId,
      hasValidLocalCache: hasValidLocalCache,
    );

    if (_hasLoadedRemoteState) {
      // Se há alterações pendentes na outbox offline de sessão anterior e o cache local é válido, aplica-as na memória
      if (_outbox.isNotEmpty) {
        final prefs = store.exportPreferencesMap();
        applyChangesToDatabase(
          db: store.db,
          prefs: prefs,
          changes: _outbox.values.toList(),
          baseline: _baseline,
        );
        store.onRemoteChangesApplied(updatedPrefs: prefs);
      }
      seedBaseline(store.db, store.exportPreferencesMap());
    } else {
      _baseline.clear();
    }

    registerWebSyncListeners(
      onOnline: () {
        _wsFailCount = 0;
        _nextWsAttemptAt = null;
        _ensureWebSocket();
        syncNow();
      },
      onOffline: () {
        _wsConnected = false;
        CloudSyncService.instance.setSyncEngineStatus(
          state: CloudSyncState.error,
          pendingCount: _outbox.length,
        );
        notifyListeners();
      },
      onVisibleOrFocus: () {
        if (CloudSyncService.instance.isAuthenticated) {
          _ensureWebSocket();
          syncNow();
        }
      },
      onBroadcastMessage: (msg) {
        if (!CloudSyncService.instance.isAuthenticated) return;
        if (msg.startsWith('sync:${CloudSyncService.instance.userId}:')) {
          syncNow();
        }
      },
    );

    _isRunning = true;
    _startTimers();
    _ensureWebSocket();
    if (triggerInitialSync) {
      syncNow(forceFullPull: !_hasLoadedRemoteState);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isRunning) {
      if (CloudSyncService.instance.isAuthenticated) {
        _ensureWebSocket();
        syncNow();
      }
    }
  }

  void stop() {
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    _isRunning = false;
    _hasLoadedRemoteState = false;
    _lastSeq = 0;
    _baseline.clear();
    _outbox.clear();
    _deltaPollTimer?.cancel();
    _deltaPollTimer = null;
    _wsPingTimer?.cancel();
    _wsPingTimer = null;
    _flushTimer?.cancel();
    _flushTimer = null;
    _compactTimer?.cancel();
    _compactTimer = null;
    _ws?.close();
    _ws = null;
    _wsConnected = false;
  }

  /// Sincroniza o estado interno do SyncEngine imediatamente após upload completo (PUT /api/db) ou restauração de backup
  void onFullDatabaseReplaced({
    required Database db,
    required Map<String, dynamic> prefs,
    required int revision,
  }) {
    _outbox.clear();
    _lastSeq = revision;
    _hasLoadedRemoteState = revision > 0;
    seedBaseline(db, prefs);
    _persistState();
    _persistLocalCache();
    if (CloudSyncService.instance.isAuthenticated) {
      broadcastWebSyncSignal(
        'sync:${CloudSyncService.instance.userId}:$_lastSeq',
      );
    }
  }

  void resetForAccountSwitch(Database db, Map<String, dynamic> prefs) {
    _outbox.clear();
    _baseline.clear();
    _lastSeq = 0;
    _hasLoadedRemoteState = false;
    if (CloudSyncService.instance.isAuthenticated) {
      _ws?.close();
      _ws = null;
      _wsConnected = false;
      _ensureWebSocket();
      syncNow(forceFullPull: true);
    }
  }

  void _loadPersistedState(
    String userId, {
    required bool hasValidLocalCache,
  }) {
    if (userId.isEmpty) return;

    if (hasValidLocalCache) {
      final rawSeq = webLocalStorageGet(_seqStorageKey(userId));
      _lastSeq = rawSeq != null ? (int.tryParse(rawSeq) ?? 0) : 0;
      _hasLoadedRemoteState = _lastSeq > 0;
    } else {
      // Se não há cache local válido carregado em memória (ex: bases grandes na Web ou novo login),
      // obriga pull completo do snapshot binário antes de habilitar diffs locais!
      _lastSeq = 0;
      _hasLoadedRemoteState = false;
    }

    _outbox.clear();
    final rawOutbox = webLocalStorageGet(_outboxStorageKey(userId));
    if (rawOutbox != null && rawOutbox.isNotEmpty) {
      try {
        final list = jsonDecode(rawOutbox);
        if (list is List) {
          for (final item in list) {
            if (item is Map) {
              final ch = SyncChange.fromJson(Map<String, dynamic>.from(item));
              if (ch.coll.isNotEmpty && ch.id.isNotEmpty) {
                _outbox['${ch.coll}/${ch.id}'] = ch;
              }
            }
          }
        }
      } catch (_) {}
    }
  }

  void _persistState() {
    final userId = CloudSyncService.instance.userId;
    if (userId.isEmpty) return;
    if (_lastSeq > 0) {
      webLocalStorageSet(_seqStorageKey(userId), _lastSeq.toString());
    }
    if (_outbox.isEmpty) {
      webLocalStorageRemove(_outboxStorageKey(userId));
    } else {
      final list = _outbox.values.map((e) => e.toJson()).toList();
      webLocalStorageSet(_outboxStorageKey(userId), jsonEncode(list));
    }
  }

  void _persistLocalCache() {
    if (_store == null || !_hasLoadedRemoteState) return;
    final userId = CloudSyncService.instance.userId;
    if (userId.isEmpty) return;
    try {
      final payloadMap = _store!.db.toJson();
      final encoded = jsonEncode({
        'revision': _lastSeq,
        'updatedAt': DateTime.now().toIso8601String(),
        'payload': payloadMap,
        'preferences': _store!.exportPreferencesMap(),
      });
      if (kIsWeb) {
        if (encoded.length < 2000000) {
          webLocalStorageSet(_cacheStorageKey(userId), encoded);
        } else {
          webLocalStorageRemove(_cacheStorageKey(userId));
        }
      } else {
        // No Desktop/Mobile, grava no arquivo de cache isolado sem limite de 2MB
        webLocalStorageSet(_cacheStorageKey(userId), encoded);
      }
    } catch (_) {}
  }

  void _scheduleClientCompaction() {
    _compactTimer?.cancel();
    _compactTimer = Timer(const Duration(seconds: 4), () async {
      if (!_isRunning ||
          _isSyncing ||
          !_hasLoadedRemoteState ||
          _outbox.isNotEmpty ||
          _lastSeq <= 0 ||
          _store == null) {
        return;
      }
      final cloud = CloudSyncService.instance;
      if (!cloud.isAuthenticated || !webIsOnline()) return;
      // Proteção extra: nunca compacta se a memória estiver vazia mas o baseline era grande
      if (_baseline.length > 20 &&
          _store!.db.txs.isEmpty &&
          _store!.db.accounts.length <= 1) {
        return;
      }
      await cloud.pushDatabase(
        payload: _store!.db.toJson(),
        preferences: _store!.exportPreferencesMap(),
        compactSeq: _lastSeq,
      );
    });
  }

  // ==========================================================================
  // Captura Automática em store.save()
  // ==========================================================================

  void onLocalSave(Database db, Map<String, dynamic> prefs) {
    if (_isApplyingRemote || !_hasLoadedRemoteState) return;
    final cloud = CloudSyncService.instance;
    if (!cloud.isAuthenticated) return;

    // Trava de segurança: bloqueia geração acidental de tombstones em massa se a memória
    // foi reiniciada sem passar pelo fluxo explícito de resetToBlankDatabaseAndSync
    if (_baseline.length > 20 && db.txs.isEmpty && db.accounts.length <= 1) {
      return;
    }

    final diffs = computeDiff(
      baseline: _baseline,
      db: db,
      prefs: prefs,
    );
    if (diffs.isEmpty && _outbox.isEmpty) return;

    for (final ch in diffs) {
      _outbox['${ch.coll}/${ch.id}'] = ch;
    }
    _persistState();
    _persistLocalCache();

    if (!webIsOnline()) {
      CloudSyncService.instance.setSyncEngineStatus(
        state: CloudSyncState.error,
        pendingCount: _outbox.length,
      );
      notifyListeners();
      return;
    }

    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 60), () {
      syncNow();
    });
  }

  // ==========================================================================
  // Loop de Sincronização Real-Time (Outbox Flush + Delta Pull + WebSocket)
  // ==========================================================================

  void _startTimers() {
    _deltaPollTimer?.cancel();
    int tick = 0;
    _deltaPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_isRunning || !CloudSyncService.instance.isAuthenticated) return;
      tick++;
      final visible = webIsDocumentVisible();
      // Quando visível: sincroniza delta a cada 2s (ou 6s se WebSocket estiver ativo)
      // Quando em segundo plano: sincroniza a cada 14s
      if (visible) {
        if (!_wsConnected || _outbox.isNotEmpty || tick % 3 == 0) {
          syncNow();
        }
      } else if (tick % 7 == 0) {
        syncNow();
      }
    });

    _wsPingTimer?.cancel();
    _wsPingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_wsConnected && _ws != null && _ws!.isOpen) {
        _ws!.send(jsonEncode({'type': 'ping'}));
      } else if (_isRunning &&
          CloudSyncService.instance.isAuthenticated &&
          webIsOnline()) {
        _ensureWebSocket();
      }
    });
  }

  void _ensureWebSocket() {
    if (!_isRunning) return;
    final cloud = CloudSyncService.instance;
    if (!cloud.isAuthenticated || !webIsOnline()) return;
    if (_ws != null && _ws!.isOpen) return;

    if (_nextWsAttemptAt != null &&
        DateTime.now().isBefore(_nextWsAttemptAt!)) {
      return;
    }

    final base = cloud.resolvedBaseUrl;
    if (base.isEmpty) return;
    final wsBase = base.startsWith('https://')
        ? base.replaceFirst('https://', 'wss://')
        : (base.startsWith('http://')
            ? base.replaceFirst('http://', 'ws://')
            : 'wss://$base');
    final wsUrl =
        '$wsBase/api/sync?token=${Uri.encodeQueryComponent(cloud.authToken)}';

    _ws?.close();
    _ws = PlatformWebSocket.connect(
      wsUrl,
      onOpen: () {
        _wsConnected = true;
        _wsFailCount = 0;
        _nextWsAttemptAt = null;
        notifyListeners();
      },
      onMessage: (rawMsg) {
        _handleWebSocketMessage(rawMsg);
      },
      onClose: () {
        _wsConnected = false;
        _wsFailCount++;
        // Backoff exponencial caso o Durable Object não esteja vinculado no painel
        final backoffSec = (_wsFailCount <= 2)
            ? 15
            : (_wsFailCount <= 5 ? 60 : 300);
        _nextWsAttemptAt = DateTime.now().add(Duration(seconds: backoffSec));
        notifyListeners();
      },
    );
  }

  void _handleWebSocketMessage(String rawMsg) {
    try {
      final decoded = jsonDecode(rawMsg);
      if (decoded is! Map) return;
      final type = decoded['type']?.toString() ?? '';
      final remoteSeq = (decoded['seq'] as num?)?.toInt() ?? 0;

      if (type == 'hello' || type == 'pong') {
        if (remoteSeq > _lastSeq) {
          syncNow();
        }
        return;
      }

      if (type == 'sync') {
        final isReset = decoded['reset'] == true;
        if (isReset) {
          syncNow(forceFullPull: true);
          return;
        }
        final rawChanges = decoded['changes'];
        if (_hasLoadedRemoteState &&
            rawChanges is List &&
            rawChanges.isNotEmpty &&
            remoteSeq == _lastSeq + 1) {
          final changes = rawChanges
              .whereType<Map>()
              .map((m) => SyncChange.fromJson(Map<String, dynamic>.from(m)))
              .toList();
          _applyIncomingDelta(changes, remoteSeq);
        } else if (remoteSeq > _lastSeq) {
          syncNow();
        }
      }
    } catch (_) {}
  }

  Future<bool> syncNow({bool forceFullPull = false}) async {
    if (_store == null) return false;
    final cloud = CloudSyncService.instance;
    if (!cloud.isAuthenticated) return false;
    if (!webIsOnline()) {
      cloud.setSyncEngineStatus(
        state: CloudSyncState.error,
        pendingCount: _outbox.length,
      );
      return false;
    }

    if (_activeSyncFuture != null) {
      if (forceFullPull) {
        _pendingForceFullPull = true;
      }
      final prevResult = await _activeSyncFuture!;
      if (_pendingForceFullPull) {
        _pendingForceFullPull = false;
        return await syncNow(forceFullPull: true);
      }
      return prevResult;
    }

    final future = _executeSyncNow(forceFullPull: forceFullPull);
    _activeSyncFuture = future;
    try {
      final result = await future;
      if (_pendingForceFullPull) {
        _pendingForceFullPull = false;
        _activeSyncFuture = null;
        return await syncNow(forceFullPull: true);
      }
      return result;
    } finally {
      if (identical(_activeSyncFuture, future)) {
        _activeSyncFuture = null;
      }
    }
  }

  Future<bool> _executeSyncNow({required bool forceFullPull}) async {
    final cloud = CloudSyncService.instance;
    _isSyncing = true;
    if (_outbox.isNotEmpty ||
        !_hasLoadedRemoteState ||
        _lastSeq == 0 ||
        forceFullPull) {
      cloud.setSyncEngineStatus(
        state: CloudSyncState.syncing,
        pendingCount: _outbox.length,
      );
    }

    try {
      // 1. Se ainda não carregou o estado inicial em memória (ou foi solicitado pull completo),
      // baixa o snapshot binário Gzip (0.5ms CPU no Worker) + deltas posteriores
      if (!_hasLoadedRemoteState || _lastSeq == 0 || forceFullPull) {
        final pulled = await _pullFullSnapshotAndDeltas();
        if (!pulled) return false;
      }

      // 2. Se há alterações locais na fila (Outbox), envia o lote atômico por registro
      if (_outbox.isNotEmpty) {
        final pushed = await _flushOutboxBatch();
        if (!pushed) return false;
      } else {
        // 3. Caso contrário, consulta delta incremental leve desde _lastSeq
        final pulled = await _pullDeltaIncremental(since: _lastSeq);
        if (!pulled) return false;
      }

      cloud.setSyncEngineStatus(
        state: CloudSyncState.synced,
        revision: _lastSeq,
        pendingCount: _outbox.length,
      );
      return true;
    } catch (e) {
      cloud.setSyncEngineStatus(
        state: CloudSyncState.error,
        pendingCount: _outbox.length,
        error: e.toString(),
      );
      return false;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Baixa o snapshot base via stream binário Gzip (suporta bases de 10MB+ sem limite de CPU no Worker)
  /// e aplica em seguida quaisquer registros de delta gravados em user_sync_records.
  Future<bool> _pullFullSnapshotAndDeltas() async {
    final cloud = CloudSyncService.instance;
    final snap = await cloud.fetchDatabase();
    if (snap == null || snap.payload.isEmpty) {
      return false;
    }

    final baseSeq = snap.snapshotSeq > 0 ? snap.snapshotSeq : snap.revision;
    _applyFullSnapshot(
      payload: snap.payload,
      preferences: snap.preferences,
      newSeq: baseSeq,
    );

    if (snap.syncSeq > baseSeq) {
      final deltaOk = await _pullDeltaIncremental(
        since: baseSeq,
        allowRecursiveFullPull: false,
      );
      if (!deltaOk) return false;
      _scheduleClientCompaction();
    }
    return true;
  }

  Future<bool> _pullDeltaIncremental({
    required int since,
    bool allowRecursiveFullPull = true,
  }) async {
    final cloud = CloudSyncService.instance;
    final base = cloud.resolvedBaseUrl;
    if (base.isEmpty) return false;

    final res = await platformHttpRequest(
      method: 'GET',
      url: '$base/api/sync?since=$since',
      headers: {
        'Authorization': 'Bearer ${cloud.authToken}',
      },
      timeout: const Duration(seconds: 25),
    );

    if (res.statusCode == 401) {
      cloud.setSyncEngineStatus(
        state: CloudSyncState.error,
        pendingCount: _outbox.length,
        error: 'Sessão expirada. Reconecte sua conta Cloud.',
      );
      return false;
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      cloud.setSyncEngineStatus(
        state: CloudSyncState.error,
        pendingCount: _outbox.length,
      );
      return false;
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) return false;

    final remoteSeq = (decoded['seq'] as num?)?.toInt() ?? _lastSeq;
    final needFullReload = decoded['fullReloadRequired'] == true;

    if (needFullReload && allowRecursiveFullPull) {
      return await _pullFullSnapshotAndDeltas();
    }

    final rawChanges = decoded['changes'];
    if (rawChanges is List && rawChanges.isNotEmpty) {
      final changes = rawChanges
          .whereType<Map>()
          .map((m) => SyncChange.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      _applyIncomingDelta(changes, remoteSeq);
    } else if (remoteSeq > _lastSeq) {
      _lastSeq = remoteSeq;
      _persistState();
    }

    return true;
  }

  Future<bool> _flushOutboxBatch() async {
    if (_outbox.isEmpty || _store == null || !_hasLoadedRemoteState) {
      return true;
    }
    final cloud = CloudSyncService.instance;
    final base = cloud.resolvedBaseUrl;
    if (base.isEmpty) return false;

    final batchEntries = Map<String, SyncChange>.from(_outbox);
    final opId =
        '${cloud.userId}_${DateTime.now().microsecondsSinceEpoch}_${batchEntries.length}';

    final res = await platformHttpRequest(
      method: 'POST',
      url: '$base/api/sync',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${cloud.authToken}',
      },
      body: jsonEncode({
        'opId': opId,
        'since': _lastSeq,
        'changes': batchEntries.values.map((c) => c.toJson()).toList(),
      }),
      timeout: const Duration(seconds: 25),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      cloud.setSyncEngineStatus(
        state: CloudSyncState.error,
        pendingCount: _outbox.length,
      );
      return false;
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic> || decoded['ok'] != true) {
      return false;
    }

    final needFullReload = decoded['fullReloadRequired'] == true;
    if (needFullReload) {
      return await _pullFullSnapshotAndDeltas();
    }

    // Remove da outbox apenas os itens que não sofreram nova edição local durante o request
    batchEntries.forEach((key, sentChange) {
      final currentInOutbox = _outbox[key];
      if (identical(currentInOutbox, sentChange)) {
        _outbox.remove(key);
      }
    });

    final newSeq = (decoded['seq'] as num?)?.toInt() ?? _lastSeq;

    final rawRemote = decoded['remoteChanges'];
    if (rawRemote is List && rawRemote.isNotEmpty) {
      final remoteChanges = rawRemote
          .whereType<Map>()
          .map((m) => SyncChange.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      _applyIncomingDelta(remoteChanges, newSeq);
    } else {
      _lastSeq = newSeq;
      _persistState();
      _persistLocalCache();
    }

    // Agenda compactação binária Gzip em background pelo cliente (zero CPU no Worker)
    _scheduleClientCompaction();

    // Notifica outras abas do mesmo navegador instantaneamente (0ms)
    broadcastWebSyncSignal('sync:${cloud.userId}:$_lastSeq');
    return true;
  }

  void _applyFullSnapshot({
    required Map<String, dynamic> payload,
    required Map<String, dynamic> preferences,
    required int newSeq,
  }) {
    final store = _store;
    if (store == null) return;

    final existingTxCount = store.db.txs.length;
    final incomingTxs = (payload['txs'] as List?)?.length ?? 0;

    // Anti-Wipe Guard: se a base local já possui lançamentos e o snapshot remoto veio vazio com revisão zero,
    // aborta a substituição destrutiva para proteger a integridade dos dados locais
    if (existingTxCount >= 10 && incomingTxs == 0 && newSeq == 0) {
      debugPrint(
        '[SyncEngine] Anti-Wipe: snapshot remoto vazio ignorado pois base local possui $existingTxCount lançamentos.',
      );
      return;
    }

    // Safety Backup pré-substituição remota
    if (existingTxCount > 0 && !kIsWeb) {
      try {
        BackupManager.instance.createSafetyBackup(
          appSupportDirPath: store.appSupportDirPath,
          reason: 'pre-remote-snapshot',
          jsonContent: jsonEncode(store.db.toJson()),
        );
      } catch (_) {}
    }

    _isApplyingRemote = true;
    try {
      store.db = Database.fromJson(payload);
      final mergedPrefs = store.exportPreferencesMap()..addAll(preferences);

      // Se houver edições locais pendentes na outbox, reaplica por cima do snapshot remoto
      if (_outbox.isNotEmpty) {
        applyChangesToDatabase(
          db: store.db,
          prefs: mergedPrefs,
          changes: _outbox.values.toList(),
          baseline: _baseline,
        );
      }

      store.onRemoteChangesApplied(updatedPrefs: mergedPrefs);
      seedBaseline(store.db, store.exportPreferencesMap());
      _lastSeq = newSeq > 0 ? newSeq : 1;
      _hasLoadedRemoteState = true;
      _persistState();
      _persistLocalCache();
    } finally {
      _isApplyingRemote = false;
    }
  }

  void _applyIncomingDelta(List<SyncChange> changes, int newSeq) {
    final store = _store;
    if (store == null) return;

    // Filtra chaves que ainda possuem edição local mais nova aguardando envio na outbox
    final filtered = changes
        .where((ch) => !_outbox.containsKey('${ch.coll}/${ch.id}'))
        .toList();

    _isApplyingRemote = true;
    try {
      if (filtered.isNotEmpty) {
        final prefs = store.exportPreferencesMap();
        final modified = applyChangesToDatabase(
          db: store.db,
          prefs: prefs,
          changes: filtered,
          baseline: _baseline,
        );
        if (modified) {
          store.onRemoteChangesApplied(updatedPrefs: prefs);
          seedBaseline(store.db, store.exportPreferencesMap());
        }
      }
      if (newSeq > 0) {
        _lastSeq = newSeq;
      }
      _hasLoadedRemoteState = true;
      _persistState();
      _persistLocalCache();
    } finally {
      _isApplyingRemote = false;
    }
  }
}

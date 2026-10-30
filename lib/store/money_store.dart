import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/openmoney_models.dart';
import '../services/audit_log_manager.dart';
import '../services/backup_manager.dart';
import '../services/cash_flow_engine.dart';
import '../services/importers_exporters.dart';

enum NavModule {
  account,
  cashFlow,
  reports,
  budget,
  categories,
  search,
  dueBills,
  installments,
}

enum ScopeChoice {
  only,
  forward,
  all,
  cancel,
}

class AccountMonthData {
  final int openingReal;
  final int openingPred;
  final List<Transaction> transactions;

  const AccountMonthData({
    required this.openingReal,
    required this.openingPred,
    required this.transactions,
  });
}

class BatchDeletePreview {
  final int count;
  final int incomeCents;
  final int expenseCents;
  final int netCents;
  final int affectedAccountsCount;

  const BatchDeletePreview({
    required this.count,
    required this.incomeCents,
    required this.expenseCents,
    required this.netCents,
    required this.affectedAccountsCount,
  });
}

class _PayeeCacheEntry {
  String name;
  String cat;
  bool isExpense;
  int count;
  String lastDate;

  _PayeeCacheEntry({
    required this.name,
    required this.cat,
    required this.isExpense,
    required this.count,
    required this.lastDate,
  });
}

class MoneyStore extends ChangeNotifier {
  Database db = Database();
  String dbPath = '';
  NavModule activeModule = NavModule.account;
  String selectedAccountId = 'a1';
  int reminderDaysAhead = 3;
  bool isDarkMode = true;
  static const List<double> kFontScales = [0.90, 1.00, 1.15, 1.30, 1.45];
  double fontScale = 1.0;
  bool sidebarShowFavorites = true;
  bool sidebarShowActiveAccounts = true;
  bool sidebarShowInactiveAccounts = false;
  bool sidebarShowPlanning = true;
  bool sidebarShowModules = false;
  bool showMissingDatabasePrompt = false;
  bool showWelcomeScreen = false;
  String missingDatabasePath = '';
  List<RecentFileItem> recentFiles = [];
  ImportSummary? lastImportSummary;
  PredictionsAdjustResult? lastPredictionsResult;
  String? highlightedTxId;
  String _month = todayISO().substring(0, 7);

  String get month => _month;
  set month(String value) {
    if (_month != value) {
      _month = value;
      syncRecs();
      rebuildPredictedBalances();
      notifyListeners();
    }
  }

  void navigateTo(NavModule module, {String? accountId}) {
    activeModule = module;
    if (accountId != null) {
      selectedAccountId = accountId;
    }
    notifyListeners();
  }

  String get databaseDisplayName {
    if (dbPath.isEmpty) return 'openmoney.json';
    final norm = dbPath.replaceAll('\\', '/');
    final parts = norm.split('/');
    final name = parts.isNotEmpty ? parts.last : '';
    return name.isEmpty ? 'openmoney.json' : name;
  }

  String get windowTitle => 'OpenMoney — $databaseDisplayName';

  // Fast In-Memory Indexing for 30k+ Transactions
  final Map<String, ({int real, int pred})> _cachedBalances = {};
  int _cachedTotalReal = 0;
  int _cachedTotalPred = 0;
  Map<String, List<Transaction>> _cachedTxsByAccount = {};
  Map<String, List<Transaction>> _cachedTxsByMonth = {};
  Map<String, _PayeeCacheEntry> _cachedPayeeSuggestions = {};
  bool _indexesDirty = true;

  Timer? _debounceSaveTimer;
  StreamSubscription<FileSystemEvent>? _fileWatcherSub;
  DateTime? _lastSavedModificationDate;
  late final String _appSupportDirPath;
  late final String _configFilePath;
  late final String _defaultDbFilePath;

  MoneyStore({bool autoBoot = true}) {
    _initPaths();
    if (autoBoot) {
      boot();
    }
  }

  void _initPaths() {
    if (kIsWeb) {
      _appSupportDirPath = '';
      _configFilePath = '';
      _defaultDbFilePath = 'openmoney.json';
      return;
    }
    final sep = Platform.pathSeparator;
    String baseDir;
    if (Platform.isWindows) {
      baseDir = Platform.environment['APPDATA'] ??
          '${Platform.environment['USERPROFILE'] ?? '.'}${sep}AppData${sep}Roaming';
    } else if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '.';
      baseDir = '$home/Library/Application Support';
    } else {
      final home = Platform.environment['HOME'] ?? '.';
      baseDir = '$home/.local/share';
    }
    _appSupportDirPath = '$baseDir${sep}OpenMoneyNew';
    _configFilePath = '$_appSupportDirPath${sep}config.json';
    _defaultDbFilePath = '$_appSupportDirPath${sep}openmoney.json';
  }

  String defaultCloudOrDocumentsDir() {
    if (kIsWeb) return '';
    final sep = Platform.pathSeparator;
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '';
      final icloud = '$home/Library/Mobile Documents/com~apple~CloudDocs';
      if (Directory(icloud).existsSync()) return icloud;
      return '$home/Documents';
    } else if (Platform.isWindows) {
      final oneDrive = Platform.environment['OneDrive'] ??
          Platform.environment['OneDriveConsumer'];
      if (oneDrive != null &&
          oneDrive.isNotEmpty &&
          Directory(oneDrive).existsSync()) {
        return oneDrive;
      }
      final userProfile = Platform.environment['USERPROFILE'] ?? '.';
      return '$userProfile${sep}Documents';
    }
    return _appSupportDirPath;
  }

  Map<String, dynamic> _readConfig() {
    if (kIsWeb || _configFilePath.isEmpty) return {};
    try {
      final f = File(_configFilePath);
      if (!f.existsSync()) return {};
      final decoded = jsonDecode(f.readAsStringSync());
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return {};
  }

  void _writeConfig(Map<String, dynamic> cfg) {
    if (kIsWeb || _configFilePath.isEmpty) return;
    try {
      Directory(_appSupportDirPath).createSync(recursive: true);
      File(_configFilePath).writeAsStringSync(jsonEncode(cfg), flush: true);
    } catch (_) {}
  }

  void boot() {
    if (kIsWeb) {
      migrate();
      syncRecs();
      syncCards(settleCardInvoices: _shouldSettleImportedCardInvoicesOnLoad());
      rebuildIndexes();
      notifyListeners();
      return;
    }

    try {
      Directory(_appSupportDirPath).createSync(recursive: true);
    } catch (_) {}

    final cfg = _readConfig();
    if (cfg['recentFiles'] is List) {
      recentFiles = (cfg['recentFiles'] as List)
          .whereType<Map>()
          .map((m) => RecentFileItem.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    }
    if (cfg['reminderDaysAhead'] is num) {
      reminderDaysAhead =
          (cfg['reminderDaysAhead'] as num).toInt().clamp(1, 60);
    }
    if (cfg['isDarkMode'] is bool) {
      isDarkMode = cfg['isDarkMode'] as bool;
    }
    if (cfg['fontScale'] is num) {
      final s = (cfg['fontScale'] as num).toDouble();
      if (s >= 0.80 && s <= 1.80) {
        fontScale = s;
      }
    }
    if (cfg['sidebarShowFavorites'] is bool) {
      sidebarShowFavorites = cfg['sidebarShowFavorites'] as bool;
    }
    if (cfg['sidebarShowActiveAccounts'] is bool) {
      sidebarShowActiveAccounts = cfg['sidebarShowActiveAccounts'] as bool;
    }
    if (cfg['sidebarShowInactiveAccounts'] is bool) {
      sidebarShowInactiveAccounts = cfg['sidebarShowInactiveAccounts'] as bool;
    }
    if (cfg['sidebarShowPlanning'] is bool) {
      sidebarShowPlanning = cfg['sidebarShowPlanning'] as bool;
    }
    if (cfg['sidebarShowModules'] is bool) {
      sidebarShowModules = cfg['sidebarShowModules'] as bool;
    }

    final configuredPath = (cfg['dbPath'] as String?)?.trim() ?? '';
    final hasConfiguredPath = configuredPath.isNotEmpty;

    // Se é a primeira vez (sem arquivo configurado e sem arquivo padrão existente),
    // abre a tela de Boas-Vindas para escolher ou criar via gerenciador de arquivos nativo
    if (!hasConfiguredPath && !File(_defaultDbFilePath).existsSync()) {
      showWelcomeScreen = true;
      dbPath = '';
      db = Database();
      rebuildIndexes();
      notifyListeners();
      return;
    }

    if (hasConfiguredPath && !File(configuredPath).existsSync()) {
      missingDatabasePath = configuredPath;
      showMissingDatabasePrompt = true;
      dbPath = '';
      db = Database();
      rebuildIndexes();
      notifyListeners();
      return;
    }

    final targetPath = hasConfiguredPath ? configuredPath : _defaultDbFilePath;
    dbPath = targetPath;

    if (File(targetPath).existsSync()) {
      try {
        final raw = File(targetPath).readAsStringSync();
        final jsonMap = jsonDecode(raw) as Map<String, dynamic>;
        db = Database.fromJson(jsonMap);
      } catch (_) {
        db = Database();
      }
    } else {
      db = Database();
    }

    migrate();
    syncRecs();
    syncCards(settleCardInvoices: _shouldSettleImportedCardInvoicesOnLoad());
    rebuildIndexes();
    if (db.accounts.isNotEmpty) {
      selectedAccountId = db.accounts.first.id;
    }

    save(immediate: true);
    registerRecentFile(targetPath);
    _setupFileWatcher(targetPath);
    notifyListeners();
  }

  void toggleThemeMode() {
    isDarkMode = !isDarkMode;
    final cfg = _readConfig();
    cfg['isDarkMode'] = isDarkMode;
    _writeConfig(cfg);
    notifyListeners();
  }

  String get fontScaleLabel {
    final pct = (fontScale * 100).round();
    if ((fontScale - 1.0).abs() < 0.01) return '100% (Padrão)';
    return '$pct%';
  }

  void setFontScale(double scale) {
    final clamped = (scale * 100).round() / 100.0;
    fontScale = clamped.clamp(0.85, 1.60);
    final cfg = _readConfig();
    cfg['fontScale'] = fontScale;
    _writeConfig(cfg);
    notifyListeners();
  }

  void zoomIn() {
    for (final s in kFontScales) {
      if (s > fontScale + 0.02) {
        setFontScale(s);
        return;
      }
    }
  }

  void zoomOut() {
    for (int i = kFontScales.length - 1; i >= 0; i--) {
      final s = kFontScales[i];
      if (s < fontScale - 0.02) {
        setFontScale(s);
        return;
      }
    }
  }

  void resetZoom() {
    setFontScale(1.0);
  }

  void toggleSidebarFavorites() {
    sidebarShowFavorites = !sidebarShowFavorites;
    final cfg = _readConfig();
    cfg['sidebarShowFavorites'] = sidebarShowFavorites;
    _writeConfig(cfg);
    notifyListeners();
  }

  void toggleSidebarActiveAccounts() {
    sidebarShowActiveAccounts = !sidebarShowActiveAccounts;
    final cfg = _readConfig();
    cfg['sidebarShowActiveAccounts'] = sidebarShowActiveAccounts;
    _writeConfig(cfg);
    notifyListeners();
  }

  void toggleSidebarInactiveAccounts() {
    sidebarShowInactiveAccounts = !sidebarShowInactiveAccounts;
    final cfg = _readConfig();
    cfg['sidebarShowInactiveAccounts'] = sidebarShowInactiveAccounts;
    _writeConfig(cfg);
    notifyListeners();
  }

  void toggleSidebarPlanning() {
    sidebarShowPlanning = !sidebarShowPlanning;
    final cfg = _readConfig();
    cfg['sidebarShowPlanning'] = sidebarShowPlanning;
    _writeConfig(cfg);
    notifyListeners();
  }

  void toggleSidebarModules() {
    sidebarShowModules = !sidebarShowModules;
    final cfg = _readConfig();
    cfg['sidebarShowModules'] = sidebarShowModules;
    _writeConfig(cfg);
    notifyListeners();
  }

  void setReminderDaysAhead(int days) {
    reminderDaysAhead = days.clamp(1, 60);
    final cfg = _readConfig();
    cfg['reminderDaysAhead'] = reminderDaysAhead;
    _writeConfig(cfg);
    notifyListeners();
  }

  void _setupFileWatcher(String path) {
    _fileWatcherSub?.cancel();
    _fileWatcherSub = null;
    if (kIsWeb || path.isEmpty) return;
    try {
      final file = File(path);
      final dir = file.parent;
      if (dir.existsSync()) {
        _fileWatcherSub = dir.watch(events: FileSystemEvent.modify).listen((e) {
          if (e.path == path || e.path.endsWith(databaseDisplayName)) {
            reloadFromDiskIfNeeded();
          }
        });
      }
    } catch (_) {}
  }

  void reloadFromDiskIfNeeded() {
    if (kIsWeb || dbPath.isEmpty) return;
    try {
      final f = File(dbPath);
      if (!f.existsSync()) return;
      final modDate = f.lastModifiedSync();
      if (_lastSavedModificationDate != null &&
          !modDate.isAfter(_lastSavedModificationDate!)) {
        return;
      }
      reloadFromDisk();
    } catch (_) {}
  }

  void reloadFromDisk() {
    if (kIsWeb || dbPath.isEmpty) return;
    try {
      final f = File(dbPath);
      if (!f.existsSync()) return;
      final raw = f.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      db = Database.fromJson(decoded);
      migrate();
      syncRecs();
      syncCards(settleCardInvoices: _shouldSettleImportedCardInvoicesOnLoad());
      rebuildIndexes();
      _lastSavedModificationDate = f.lastModifiedSync();
      notifyListeners();
    } catch (_) {}
  }

  bool openDatabaseFromPath(String path) {
    if (kIsWeb || path.isEmpty) return false;
    try {
      final f = File(path);
      if (!f.existsSync()) {
        debugPrint('[OpenMoney] Arquivo não encontrado: $path');
        return false;
      }
      final raw = f.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final loaded = Database.fromJson(decoded);

      dbPath = path;
      db = loaded;
      migrate();
      syncRecs();
      syncCards(settleCardInvoices: _shouldSettleImportedCardInvoicesOnLoad());
      rebuildIndexes();
      if (db.accounts.isNotEmpty) {
        selectedAccountId = db.accounts.first.id;
        activeModule = NavModule.account;
      }

      final cfg = _readConfig();
      cfg['dbPath'] = path;
      _writeConfig(cfg);

      save(immediate: true);
      registerRecentFile(path);
      _setupFileWatcher(path);
      showMissingDatabasePrompt = false;
      showWelcomeScreen = false;
      notifyListeners();
      return true;
    } catch (e, st) {
      debugPrint('[OpenMoney] Erro ao carregar base $path: $e\n$st');
      return false;
    }
  }

  void loadFromJsonString(String rawJson, {String virtualPath = ''}) {
    final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
    db = Database.fromJson(decoded);
    if (virtualPath.isNotEmpty) {
      dbPath = virtualPath;
    }
    migrate();
    syncRecs();
    syncCards(settleCardInvoices: _shouldSettleImportedCardInvoicesOnLoad());
    rebuildIndexes();
    if (db.accounts.isNotEmpty) {
      selectedAccountId = db.accounts.first.id;
    }
    notifyListeners();
  }

  void createNewDatabaseAtPath(String path) {
    db = Database(
      accounts: [
        Account(id: 'a1', name: 'Conta Corrente', type: 'Corrente', opening: 0),
      ],
      cats: List<CategoryItem>.from(kDefaultCats),
      txs: [],
      recs: [],
      budgets: {},
      v: 6,
    );
    dbPath = path;
    final cfg = _readConfig();
    cfg['dbPath'] = path;
    _writeConfig(cfg);
    rebuildIndexes();
    selectedAccountId = 'a1';
    activeModule = NavModule.account;
    showMissingDatabasePrompt = false;
    showWelcomeScreen = false;
    save(immediate: true);
    registerRecentFile(path);
    _setupFileWatcher(path);
    notifyListeners();
  }

  void moveDatabaseToPath(String newPath) {
    if (newPath.isEmpty) return;
    dbPath = newPath;
    final cfg = _readConfig();
    cfg['dbPath'] = newPath;
    _writeConfig(cfg);
    save(immediate: true);
    registerRecentFile(newPath);
    _setupFileWatcher(newPath);
    notifyListeners();
  }

  void registerRecentFile(String path) {
    if (path.isEmpty) return;
    final list = recentFiles.where((r) => r.path != path).toList();
    list.insert(0, RecentFileItem(path: path, lastOpened: DateTime.now()));
    if (list.length > 10) {
      recentFiles = list.sublist(0, 10);
    } else {
      recentFiles = list;
    }
    final cfg = _readConfig();
    cfg['recentFiles'] = recentFiles.map((r) => r.toJson()).toList();
    _writeConfig(cfg);
  }

  void removeRecentFile(String path) {
    recentFiles.removeWhere((r) => r.path == path);
    final cfg = _readConfig();
    cfg['recentFiles'] = recentFiles.map((r) => r.toJson()).toList();
    _writeConfig(cfg);
    notifyListeners();
  }

  void clearRecentFiles() {
    recentFiles.clear();
    final cfg = _readConfig();
    cfg['recentFiles'] = [];
    _writeConfig(cfg);
    notifyListeners();
  }

  String exportDatabaseJson({bool pretty = true}) {
    if (pretty) {
      return const JsonEncoder.withIndent('  ').convert(db.toJson());
    }
    return jsonEncode(db.toJson());
  }

  void markIndexesDirty() {
    _indexesDirty = true;
  }

  void rebuildIndexesIfNeeded() {
    if (_indexesDirty) {
      rebuildIndexes();
    }
  }

  void rebuildIndexes() {
    final realByAcc = <String, int>{};
    final predByAcc = <String, int>{};
    final byAcc = <String, List<Transaction>>{};
    final byMonth = <String, List<Transaction>>{};
    final payeeMap = <String, _PayeeCacheEntry>{};

    final cardAccounts = <String, Account>{};
    for (final acc in db.accounts) {
      realByAcc[acc.id] = acc.opening;
      predByAcc[acc.id] = acc.opening;
      byAcc[acc.id] = [];
      if (acc.type == kCardType && acc.card != null) {
        cardAccounts[acc.id] = acc;
      }
    }

    final endOfMonth = '$_month-31';

    for (final tx in db.txs) {
      byAcc.putIfAbsent(tx.acc, () => []).add(tx);
      final mPrefix = tx.date.length >= 7 ? tx.date.substring(0, 7) : tx.date;
      byMonth.putIfAbsent(mPrefix, () => []).add(tx);

      if (tx.rec) {
        realByAcc[tx.acc] = (realByAcc[tx.acc] ?? 0) + tx.amt;
      }

      final cardAcc = cardAccounts[tx.acc];
      if (cardAcc != null) {
        // Conta tipo Cartão de crédito: não duplica pagamento automático de fatura no previsto
        // e compras consideram a chave/mês da fatura (ik)
        if (tx.auto != true) {
          final ik = tx.ik ?? invKeyFor(cardAcc.card!, tx.date);
          if (ik.compareTo(_month) <= 0) {
            predByAcc[tx.acc] = (predByAcc[tx.acc] ?? 0) + tx.amt;
          }
        }
      } else {
        if (tx.rec || tx.date.compareTo(endOfMonth) <= 0) {
          predByAcc[tx.acc] = (predByAcc[tx.acc] ?? 0) + tx.amt;
        }
      }

      if (tx.auto != true && tx.xfer == null) {
        final raw = tx.payee.trim();
        if (raw.isNotEmpty) {
          String clean = raw;
          final parenIdx = raw.lastIndexOf('(');
          if (parenIdx != -1 && raw.endsWith(')')) {
            final inner = raw.substring(parenIdx + 1, raw.length - 1);
            if (inner.contains('/')) {
              clean = raw.substring(0, parenIdx).trim();
            }
          }
          if (clean.isNotEmpty) {
            final key = clean.toLowerCase();
            final entry = payeeMap[key];
            if (entry != null) {
              entry.count += 1;
              if (tx.date.compareTo(entry.lastDate) > 0) {
                entry.lastDate = tx.date;
                entry.cat = tx.cat;
                entry.isExpense = tx.amt < 0;
              }
            } else {
              payeeMap[key] = _PayeeCacheEntry(
                name: clean,
                cat: tx.cat,
                isExpense: tx.amt < 0,
                count: 1,
                lastDate: tx.date,
              );
            }
          }
        }
      }
    }

    for (final entry in byAcc.entries) {
      entry.value.sort((a, b) {
        final dc = a.date.compareTo(b.date);
        if (dc != 0) return dc;
        final tA = a.createdAt ?? 0.0;
        final tB = b.createdAt ?? 0.0;
        if (tA != tB) return tA.compareTo(tB);
        return a.id.compareTo(b.id);
      });
    }

    int totalReal = 0;
    int totalPred = 0;
    _cachedBalances.clear();
    for (final acc in db.accounts) {
      final r = realByAcc[acc.id] ?? acc.opening;
      final p = predByAcc[acc.id] ?? acc.opening;
      _cachedBalances[acc.id] = (real: r, pred: p);
      totalReal += r;
      totalPred += p;
    }

    _cachedTotalReal = totalReal;
    _cachedTotalPred = totalPred;
    _cachedTxsByAccount = byAcc;
    _cachedTxsByMonth = byMonth;
    _cachedPayeeSuggestions = payeeMap;
    _indexesDirty = false;
  }

  void rebuildPredictedBalances() {
    final endOfMonth = '$_month-31';
    final predByAcc = <String, int>{};
    final cardAccounts = <String, Account>{};
    for (final acc in db.accounts) {
      predByAcc[acc.id] = acc.opening;
      if (acc.type == kCardType && acc.card != null) {
        cardAccounts[acc.id] = acc;
      }
    }
    for (final tx in db.txs) {
      final cardAcc = cardAccounts[tx.acc];
      if (cardAcc != null) {
        if (tx.auto != true) {
          final ik = tx.ik ?? invKeyFor(cardAcc.card!, tx.date);
          if (ik.compareTo(_month) <= 0) {
            predByAcc[tx.acc] = (predByAcc[tx.acc] ?? 0) + tx.amt;
          }
        }
      } else {
        if (tx.rec || tx.date.compareTo(endOfMonth) <= 0) {
          predByAcc[tx.acc] = (predByAcc[tx.acc] ?? 0) + tx.amt;
        }
      }
    }
    int totalPred = 0;
    for (final acc in db.accounts) {
      final p = predByAcc[acc.id] ?? acc.opening;
      final r = _cachedBalances[acc.id]?.real ?? acc.opening;
      _cachedBalances[acc.id] = (real: r, pred: p);
      totalPred += p;
    }
    _cachedTotalPred = totalPred;
  }

  void save({bool immediate = false}) {
    rebuildIndexesIfNeeded();
    notifyListeners();

    if (kIsWeb || dbPath.isEmpty) return;

    _debounceSaveTimer?.cancel();
    _debounceSaveTimer = null;

    if (immediate) {
      _performDiskWrite();
      return;
    }

    _debounceSaveTimer = Timer(const Duration(milliseconds: 350), () {
      _performDiskWrite();
    });
  }

  void _performDiskWrite() {
    if (kIsWeb || dbPath.isEmpty) return;
    try {
      final targetFile = File(dbPath);
      targetFile.parent.createSync(recursive: true);

      final encoded = jsonEncode(db.toJson());

      // Gravação direta e síncrona com flush obrigatório
      targetFile.writeAsStringSync(encoded, flush: true);
      _lastSavedModificationDate = targetFile.lastModifiedSync();
      _ensureDailyBackup(targetFile);
    } catch (_) {
      try {
        final f = File(dbPath);
        f.writeAsStringSync(jsonEncode(db.toJson()), flush: true);
        _lastSavedModificationDate = f.lastModifiedSync();
      } catch (_) {}
    }
  }

  String get appSupportDirPath => _appSupportDirPath;

  void _ensureDailyBackup(File dbFile) {
    if (kIsWeb || _appSupportDirPath.isEmpty) return;
    BackupManager.instance.ensureDailyBackup(
      appSupportDirPath: _appSupportDirPath,
      databasePath: dbFile.path,
    );
    AuditLogManager.instance.pruneOldLogs(dbPath: dbFile.path, retentionDays: 30);
  }

  Future<String?> createManualZipBackup() async {
    if (kIsWeb || dbPath.isEmpty) return null;
    return await BackupManager.instance.createTimestampedBackup(
      appSupportDirPath: _appSupportDirPath,
      databasePath: dbPath,
      prefix: 'manual',
    );
  }

  Future<String?> createAutomaticPreDeleteBackup() async {
    if (kIsWeb || dbPath.isEmpty) return null;
    return await BackupManager.instance.createTimestampedBackup(
      appSupportDirPath: _appSupportDirPath,
      databasePath: dbPath,
      prefix: 'backup-pre-exclusao',
    );
  }

  List<BackupFileInfo> availableBackups() {
    return BackupManager.instance.availableBackups(
      appSupportDirPath: _appSupportDirPath,
    );
  }

  void revealBackupsInFinder() {
    BackupManager.instance.revealInFinder(_appSupportDirPath);
  }

  String get logFilePath => AuditLogManager.instance.logFilePathForDatabase(dbPath);

  Future<List<AuditLogEntry>> readRecentAuditLogs({int limit = 500}) async {
    return await AuditLogManager.instance.readRecentLogs(
      dbPath: dbPath,
      limit: limit,
    );
  }

  void revealLogFileInFinder() {
    if (kIsWeb || dbPath.isEmpty) return;
    final logPath = logFilePath;
    if (logPath.isEmpty) return;
    final f = File(logPath);
    if (!f.existsSync()) {
      f.writeAsStringSync('');
    }
    if (Platform.isMacOS) {
      Process.run('open', ['-R', logPath]);
    } else if (Platform.isWindows) {
      Process.run('explorer.exe', ['/select,', logPath]);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [f.parent.path]);
    }
  }

  void openLogFileInEditor() {
    if (kIsWeb || dbPath.isEmpty) return;
    final logPath = logFilePath;
    if (logPath.isEmpty) return;
    final f = File(logPath);
    if (!f.existsSync()) {
      f.writeAsStringSync('');
    }
    if (Platform.isMacOS) {
      Process.run('open', [logPath]);
    } else if (Platform.isWindows) {
      Process.run('cmd.exe', ['/c', 'start', '', logPath]);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [logPath]);
    }
  }

  Future<bool> restoreDatabaseFromZip(String zipPath) async {
    final loaded = await BackupManager.instance.extractDatabase(zipPath: zipPath);
    if (loaded == null) return false;

    db = loaded;
    migrate();
    syncRecs();
    syncCards(settleCardInvoices: _shouldSettleImportedCardInvoicesOnLoad());
    rebuildIndexes();
    if (db.accounts.isNotEmpty) {
      selectedAccountId = db.accounts.first.id;
    }
    save(immediate: true);
    notifyListeners();
    return true;
  }

  // MARK: - Migration & Sync

  bool _shouldSettleImportedCardInvoicesOnLoad() {
    final cardIds = db.accounts
        .where((a) => a.type == kCardType)
        .map((a) => a.id)
        .toSet();
    if (cardIds.isEmpty) return false;
    bool hasInvPay = false;
    bool hasReconciledCardTx = false;
    for (final tx in db.txs) {
      if (tx.xfer != null && tx.xfer!.startsWith('invpay:')) {
        hasInvPay = true;
        break;
      }
      if (cardIds.contains(tx.acc) && tx.auto != true && tx.rec) {
        hasReconciledCardTx = true;
      }
    }
    return !hasInvPay && hasReconciledCardTx;
  }

  void migrate() {
    db.cats.sort(byCatSort);
    for (int i = 0; i < db.accounts.length; i++) {
      if (db.accounts[i].type == kCardType) {
        final fallbackPay = db.accounts
                .where((a) =>
                    a.id != db.accounts[i].id && a.type != kCardType)
                .firstOrNull
                ?.id ??
            db.accounts
                .where((a) => a.id != db.accounts[i].id)
                .firstOrNull
                ?.id ??
            '';
        if (db.accounts[i].card == null) {
          db.accounts[i].card = CardConfig(
            closeDay: 1,
            dueDay: 10,
            pay: fallbackPay,
          );
        } else if (db.accounts[i].card!.pay.isEmpty ||
            !db.accounts.any((a) => a.id == db.accounts[i].card!.pay)) {
          db.accounts[i].card!.pay = fallbackPay;
        }
        db.accounts[i].invoices ??= {};
      }
    }
    for (int i = 0; i < db.txs.length; i++) {
      db.txs[i].createdAt ??= 1000000.0 + i.toDouble();
    }

    if (db.v < 7) {
      // Migra chaves de faturas de cartão de crédito do padrão legado (mês de fechamento)
      // para o padrão oficial de mercado (mês de vencimento da fatura).
      for (int aIdx = 0; aIdx < db.accounts.length; aIdx++) {
        final acc = db.accounts[aIdx];
        if (acc.type != kCardType || acc.card == null) continue;
        final cardCfg = acc.card!;
        if (cardCfg.dueDay > cardCfg.closeDay) continue;

        final cardId = acc.id;
        final newInvoices = <String, InvoiceInfo>{};
        final keyMigrationMap = <String, String>{};

        if (acc.invoices != null) {
          for (final entry in acc.invoices!.entries) {
            final oldK = entry.key;
            final info = entry.value;
            final expectedDueMonth = addMonthsYM(oldK, 1);
            if (info.due.startsWith(expectedDueMonth)) {
              final newK = expectedDueMonth;
              newInvoices[newK] = info;
              keyMigrationMap[oldK] = newK;
            } else {
              newInvoices[oldK] = info;
            }
          }
          acc.invoices = newInvoices;
        }

        if (keyMigrationMap.isNotEmpty) {
          for (int tIdx = 0; tIdx < db.txs.length; tIdx++) {
            final tx = db.txs[tIdx];
            if (tx.acc == cardId && tx.ik != null) {
              final newIk = keyMigrationMap[tx.ik!];
              if (newIk != null) {
                tx.ik = newIk;
              }
            }
            if (tx.auto == true && tx.card == cardId && tx.inv != null) {
              final oldInv = tx.inv!;
              final newInv = keyMigrationMap[oldInv];
              if (newInv != null) {
                tx.inv = newInv;
                tx.xfer = 'inv:$cardId:$newInv';
                tx.memo = 'Fatura ${fmtMonth(newInv)}';
                if (tx.id.startsWith('inv:$cardId:$oldInv:')) {
                  final suffix = tx.id.length >= 2 ? tx.id.substring(tx.id.length - 2) : '';
                  tx.id = 'inv:$cardId:$newInv$suffix';
                }
              }
            }
          }
        }
      }
    }
    db.v = 7;
  }

  void syncRecs() {
    if (db.recs.isEmpty) return;
    final existingIds = db.txs.map((t) => t.id).toSet();
    final newTxs = <Transaction>[];
    final today = todayISO();

    for (int rIdx = 0; rIdx < db.recs.length; rIdx++) {
      if (db.recs[rIdx].nextSeq < 1) db.recs[rIdx].nextSeq = 1;
      final r = db.recs[rIdx];
      final int monthsAhead;
      switch (r.freq) {
        case 'yearly':
        case 'anual':
          monthsAhead = 60;
          break;
        case 'semiannual':
        case 'semestral':
          monthsAhead = 48;
          break;
        case 'quarterly':
        case 'trimestral':
          monthsAhead = 36;
          break;
        case 'bimonthly':
        case 'bimestral':
        case 'monthly':
        case 'mensal':
          monthsAhead = 24;
          break;
        default:
          monthsAhead = 12;
      }

      final h1 = addMonthsDate(today, monthsAhead);
      final h2 = '$_month-31';
      final horizon = h1.compareTo(h2) >= 0 ? h1 : h2;

      while (true) {
        final seq = db.recs[rIdx].nextSeq;
        final d = addFreqDate(r.start, r.freq, seq - 1);
        if (r.end != null && d.compareTo(r.end!) > 0) break;
        if (d.compareTo(horizon) > 0 && seq > 1) break;

        final id = 'rec:${r.id}:$seq';
        final isTransfer = r.peer != null;
        final xid = isTransfer ? 'xrec:${r.id}:$seq' : null;

        if (!existingIds.contains(id)) {
          final curAcc = accById(r.acc);
          final curIsCard = curAcc?.type == kCardType && curAcc?.card != null;
          final curIk = curIsCard ? invKeyFor(curAcc!.card!, d) : null;

          newTxs.add(
            Transaction(
              id: id,
              acc: r.acc,
              peer: r.peer,
              date: d,
              payee: r.payee,
              cat: r.cat,
              memo: r.memo,
              amt: r.amt,
              rec: d.compareTo(today) <= 0 && seq == 1,
              xfer: xid,
              ik: curIk,
              recId: r.id,
              recFreq: r.freq,
              recSeq: seq,
            ),
          );
          existingIds.add(id);
        }

        if (r.peer != null) {
          final peerId = r.peer!;
          final peerTxId = 'rec:${r.id}:$seq:peer';
          if (!existingIds.contains(peerTxId)) {
            final peerAcc = accById(peerId);
            final curAcc = accById(r.acc);
            final peerIsCard =
                peerAcc?.type == kCardType && peerAcc?.card != null;
            final peerIk = peerIsCard ? invKeyFor(peerAcc!.card!, d) : null;

            newTxs.add(
              Transaction(
                id: peerTxId,
                acc: peerId,
                peer: r.acc,
                date: d,
                payee: r.payee,
                cat: 'Transferência: ${curAcc?.name ?? ""}',
                memo: r.memo,
                amt: -r.amt,
                rec: d.compareTo(today) <= 0 && seq == 1,
                xfer: xid,
                ik: peerIk,
                recId: r.id,
                recFreq: r.freq,
                recSeq: seq,
              ),
            );
            existingIds.add(peerTxId);
          }
        }

        db.recs[rIdx].nextSeq += 1;
        if (db.recs[rIdx].nextSeq > 5000) break;
      }
    }

    if (newTxs.isNotEmpty) {
      db.txs.addAll(newTxs);
      markIndexesDirty();
    }
  }

  void syncCards({bool settleCardInvoices = false}) {
    final cards = {
      for (final a in db.accounts.where((a) => a.type == kCardType)) a.id: a
    };
    if (cards.isEmpty) {
      db.txs.removeWhere(
        (t) =>
            (t.auto == true && t.card != null) ||
            (t.xfer != null && t.xfer!.startsWith('invpay:')),
      );
      return;
    }

    db.txs.removeWhere((t) {
      final isAutoCard = t.auto == true && t.card != null;
      final isInvPay = t.xfer != null && t.xfer!.startsWith('invpay:');
      if (!isAutoCard && !isInvPay) return false;
      if (t.card != null && !cards.containsKey(t.card)) return true;
      return false;
    });

    final today = todayISO();
    final cardTxIndices = <String, List<int>>{};
    final autoTxMap = <String, int>{};
    final invPayTxMap = <String, int>{};
    final settledKeysByCard = <String, Set<String>>{};

    for (int idx = 0; idx < db.txs.length; idx++) {
      final tx = db.txs[idx];
      final isInvPay = tx.xfer != null && tx.xfer!.startsWith('invpay:');
      if (tx.auto == true) {
        autoTxMap[tx.id] = idx;
      } else if (isInvPay) {
        invPayTxMap[tx.id] = idx;
        if (tx.card != null && tx.inv != null) {
          settledKeysByCard.putIfAbsent(tx.card!, () => {}).add(tx.inv!);
        }
      } else if (cards.containsKey(tx.acc)) {
        cardTxIndices.putIfAbsent(tx.acc, () => []).add(idx);
      }
    }

    final xidsToRemove = <String>{};
    final newAutoTxs = <Transaction>[];

    for (int aIdx = 0; aIdx < db.accounts.length; aIdx++) {
      if (db.accounts[aIdx].type != kCardType ||
          db.accounts[aIdx].card == null) {
        continue;
      }
      final cardCfg = db.accounts[aIdx].card!;
      final cardId = db.accounts[aIdx].id;
      final cardName = db.accounts[aIdx].name;
      final invoices =
          Map<String, InvoiceInfo>.from(db.accounts[aIdx].invoices ?? {});
      bool invoicesModified = false;

      for (final entry in invoices.entries.toList()) {
        final k = entry.key;
        final inv = entry.value;
        if (inv.manual != true) {
          final d = invDates(cardCfg, k);
          if (d.close != inv.close ||
              d.due != inv.due ||
              cardCfg.pay != inv.pay) {
            invoices[k] = InvoiceInfo(
              close: d.close,
              due: d.due,
              pay: cardCfg.pay,
              manual: inv.manual,
            );
            invoicesModified = true;
          }
        } else if (!db.accounts.any((a) => a.id == inv.pay) &&
            cardCfg.pay.isNotEmpty) {
          invoices[k] = InvoiceInfo(
            close: inv.close,
            due: inv.due,
            pay: cardCfg.pay,
            manual: inv.manual,
          );
          invoicesModified = true;
        }
      }

      final indices = cardTxIndices[cardId] ?? [];
      final sums = <String, int>{};

      for (final tIdx in indices) {
        final ik = db.txs[tIdx].ik ?? invKeyFor(cardCfg, db.txs[tIdx].date);
        if (db.txs[tIdx].ik != ik) {
          db.txs[tIdx].ik = ik;
        }
        if (!invoices.containsKey(ik)) {
          final d = invDates(cardCfg, ik);
          invoices[ik] = InvoiceInfo(
            close: d.close,
            due: d.due,
            pay: cardCfg.pay,
          );
          invoicesModified = true;
        }
        sums[ik] = (sums[ik] ?? 0) + db.txs[tIdx].amt;
      }

      final settledForCard = settledKeysByCard[cardId] ?? const <String>{};
      final allKeys = {...invoices.keys, ...sums.keys};
      for (final k in allKeys) {
        final total = sums[k] ?? 0;
        final autoXid = 'inv:$cardId:$k';
        final payXid = 'invpay:$cardId:$k';
        final inv = invoices[k];
        if (inv == null) continue;
        final payAccExists = db.accounts.any((a) => a.id == inv.pay);

        if (total >= 0 || !payAccExists) {
          xidsToRemove.add(autoXid);
          xidsToRemove.add(payXid);
          continue;
        }

        final amt = total.abs();
        final payAccName = accById(inv.pay)?.name ?? '';
        final cat = 'Transferência: $cardName';
        final payCat = 'Transferência: $payAccName';
        final isDueOnOrBeforeToday = inv.due.compareTo(today) <= 0;
        final shouldSettle =
            (settleCardInvoices || settledForCard.isNotEmpty) &&
            isDueOnOrBeforeToday;

        if (shouldSettle) {
          xidsToRemove.add(autoXid);
          final payCardLabel =
              'Pagamento de Fatura${payAccName.isEmpty ? "" : " ($payAccName)"}';
          final paySourceLabel = 'Pagamento de Fatura: $cardName';
          final payMemo = 'Pagamento da Fatura ${fmtMonth(k)}';

          _upsertInvPayTxFast(
            invPayTxMap: invPayTxMap,
            appended: newAutoTxs,
            id: '$payXid:c',
            acc: cardId,
            peer: inv.pay,
            date: inv.due,
            payee: payCardLabel,
            cat: payCat,
            memo: payMemo,
            amt: amt,
            xfer: payXid,
            card: cardId,
            inv: k,
            ik: k,
          );
          _upsertInvPayTxFast(
            invPayTxMap: invPayTxMap,
            appended: newAutoTxs,
            id: '$payXid:p',
            acc: inv.pay,
            peer: cardId,
            date: inv.due,
            payee: paySourceLabel,
            cat: cat,
            memo: payMemo,
            amt: -amt,
            xfer: payXid,
            card: cardId,
            inv: k,
            ik: null,
          );
        } else {
          xidsToRemove.add(payXid);
          final label = 'Pagamento do Cartão "$cardName"';
          _upsertAutoTxFast(
            autoTxMap: autoTxMap,
            appended: newAutoTxs,
            id: '$autoXid:c',
            acc: cardId,
            peer: inv.pay,
            date: inv.due,
            payee: label,
            cat: payCat,
            amt: amt,
            xfer: autoXid,
            card: cardId,
            inv: k,
          );
          _upsertAutoTxFast(
            autoTxMap: autoTxMap,
            appended: newAutoTxs,
            id: '$autoXid:p',
            acc: inv.pay,
            peer: cardId,
            date: inv.due,
            payee: label,
            cat: cat,
            amt: -amt,
            xfer: autoXid,
            card: cardId,
            inv: k,
          );
        }
      }

      if (invoicesModified) {
        db.accounts[aIdx].invoices = invoices;
      }
    }

    if (xidsToRemove.isNotEmpty) {
      db.txs.removeWhere(
          (t) => t.xfer != null && xidsToRemove.contains(t.xfer!));
    }
    if (newAutoTxs.isNotEmpty) {
      db.txs.addAll(newAutoTxs);
    }
  }

  void _upsertInvPayTxFast({
    required Map<String, int> invPayTxMap,
    required List<Transaction> appended,
    required String id,
    required String acc,
    required String peer,
    required String date,
    required String payee,
    required String cat,
    required String memo,
    required int amt,
    required String xfer,
    required String card,
    required String inv,
    required String? ik,
  }) {
    final idx = invPayTxMap[id];
    if (idx != null) {
      final t = db.txs[idx];
      t.acc = acc;
      t.peer = peer;
      t.date = date;
      t.payee = payee;
      t.cat = cat;
      t.memo = memo;
      t.amt = amt;
      t.rec = true;
      t.xfer = xfer;
      t.auto = null;
      t.card = card;
      t.inv = inv;
      t.ik = ik;
    } else {
      final tx = Transaction(
        id: id,
        acc: acc,
        peer: peer,
        date: date,
        payee: payee,
        cat: cat,
        memo: memo,
        amt: amt,
        rec: true,
        xfer: xfer,
        auto: null,
        card: card,
        inv: inv,
        ik: ik,
      );
      appended.add(tx);
      invPayTxMap[id] = db.txs.length + appended.length - 1;
    }
  }

  void _upsertAutoTxFast({
    required Map<String, int> autoTxMap,
    required List<Transaction> appended,
    required String id,
    required String acc,
    required String peer,
    required String date,
    required String payee,
    required String cat,
    required int amt,
    required String xfer,
    required String card,
    required String inv,
  }) {
    final idx = autoTxMap[id];
    if (idx != null) {
      final t = db.txs[idx];
      t.acc = acc;
      t.peer = peer;
      t.date = date;
      t.payee = payee;
      t.cat = cat;
      t.amt = amt;
      t.xfer = xfer;
      t.card = card;
      t.inv = inv;
      t.auto = true;
    } else {
      final tx = Transaction(
        id: id,
        acc: acc,
        peer: peer,
        date: date,
        payee: payee,
        cat: cat,
        memo: 'Fatura ${fmtMonth(inv)}',
        amt: amt,
        rec: false,
        xfer: xfer,
        auto: true,
        card: card,
        inv: inv,
      );
      appended.add(tx);
      autoTxMap[id] = db.txs.length + appended.length - 1;
    }
  }

  // MARK: - Queries & Balances

  Account? accById(String? id) {
    if (id == null) return null;
    for (final a in db.accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  int balance(Account a, {bool predicted = false}) {
    rebuildIndexesIfNeeded();
    final pair = _cachedBalances[a.id];
    if (pair != null) {
      return predicted ? pair.pred : pair.real;
    }
    return a.opening;
  }

  int totalBalance({bool predicted = false}) {
    rebuildIndexesIfNeeded();
    return predicted ? _cachedTotalPred : _cachedTotalReal;
  }

  List<Account> get activeAccounts =>
      db.accounts.where((a) => a.isActive).toList();
  List<Account> get inactiveAccounts =>
      db.accounts.where((a) => a.isInactive).toList();
  List<Account> get favoriteAccounts =>
      db.accounts.where((a) => a.isFavorite).toList();
  List<Account> get regularActiveAccounts =>
      db.accounts.where((a) => a.isActive && !a.isFavorite).toList();
  List<Account> get regularInactiveAccounts =>
      db.accounts.where((a) => a.isInactive && !a.isFavorite).toList();

  /// Lista ordenada de todos os negócios cadastrados nas contas (sem duplicatas).
  List<String> get allBusinesses {
    final set = <String>{};
    for (final acc in db.accounts) {
      final b = acc.business?.trim();
      if (b != null && b.isNotEmpty) {
        set.add(b);
      }
    }
    final list = set.toList();
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  /// Retorna as contas ativas que pertencem a um negócio específico.
  List<Account> accountsForBusiness(String business) {
    final bNorm = business.trim().toLowerCase();
    return activeAccounts
        .where((a) => (a.business?.trim().toLowerCase() ?? '') == bNorm)
        .toList();
  }

  /// Retorna o nome do negócio de uma conta.
  String? businessForAccountId(String accId) => accById(accId)?.business;

  AccountMonthData accountMonthData(String accountId, String targetMonth) {
    rebuildIndexesIfNeeded();
    final accTxs = _cachedTxsByAccount[accountId] ?? [];
    final monthStart = '$targetMonth-01';
    final monthEnd = '$targetMonth-31';

    int low = 0;
    int high = accTxs.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (accTxs[mid].date.compareTo(monthStart) < 0) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    final startIdx = low;

    low = startIdx;
    high = accTxs.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (accTxs[mid].date.compareTo(monthEnd) <= 0) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    final endIdx = low;

    final opening = accById(accountId)?.opening ?? 0;
    int runningReal = opening;
    int runningPred = opening;
    for (int i = 0; i < startIdx; i++) {
      final t = accTxs[i];
      if (t.rec) runningReal += t.amt;
      runningPred += t.amt;
    }

    final monthTxs = accTxs.sublist(startIdx, endIdx);
    return AccountMonthData(
      openingReal: runningReal,
      openingPred: runningPred,
      transactions: monthTxs,
    );
  }

  List<Transaction> monthTransactions(String targetMonth) {
    rebuildIndexesIfNeeded();
    return _cachedTxsByMonth[targetMonth] ?? [];
  }

  List<Transaction> accountTransactions(String accountId) {
    rebuildIndexesIfNeeded();
    return _cachedTxsByAccount[accountId] ?? [];
  }

  InvoiceSummary? invoiceSummary(String cardId, String key) {
    final cardAcc = accById(cardId);
    if (cardAcc == null ||
        cardAcc.type != kCardType ||
        cardAcc.card == null) {
      return null;
    }
    final cardCfg = cardAcc.card!;
    final invInfo = cardAcc.invoices?[key] ??
        (() {
          final d = invDates(cardCfg, key);
          return InvoiceInfo(close: d.close, due: d.due, pay: cardCfg.pay);
        })();
    final payAccName = accById(invInfo.pay)?.name ?? '—';

    rebuildIndexesIfNeeded();
    final cardTxs = _cachedTxsByAccount[cardId] ?? [];

    int charges = 0;
    int payments = 0;
    for (final t in cardTxs) {
      if (t.auto == true) continue;
      final ik = t.ik ?? invKeyFor(cardCfg, t.date);
      if (ik == key) {
        if (t.amt < 0) {
          charges += t.amt.abs();
        } else if (t.amt > 0) {
          payments += t.amt;
        }
      }
    }

    final remaining = (charges - payments) > 0 ? (charges - payments) : 0;
    final isFullyPaid = charges > 0 && remaining == 0;

    return InvoiceSummary(
      key: key,
      closeDate: invInfo.close,
      dueDate: invInfo.due,
      payAccountId: invInfo.pay,
      payAccountName: payAccName,
      chargesCents: charges,
      paymentsCents: payments,
      remainingCents: remaining,
      isFullyPaid: isFullyPaid,
    );
  }

  /// Retorna os lançamentos e saldo anterior acumulado da fatura `key` de um cartão de crédito.
  AccountMonthData cardInvoiceMonthData(String cardId, String key) {
    final cardAcc = accById(cardId);
    if (cardAcc == null ||
        cardAcc.type != kCardType ||
        cardAcc.card == null) {
      return accountMonthData(cardId, key);
    }
    final cardCfg = cardAcc.card!;
    rebuildIndexesIfNeeded();
    final cardTxs = _cachedTxsByAccount[cardId] ?? [];

    int priorReal = cardAcc.opening;
    int priorPred = cardAcc.opening;
    final invTxs = <Transaction>[];

    for (final t in cardTxs) {
      if (t.auto == true) continue;
      final ik = t.ik ?? invKeyFor(cardCfg, t.date);
      if (ik.compareTo(key) < 0) {
        if (t.rec) priorReal += t.amt;
        priorPred += t.amt;
      } else if (ik == key) {
        invTxs.add(t);
      }
    }

    invTxs.sort((a, b) {
      final dc = a.date.compareTo(b.date);
      if (dc != 0) return dc;
      final tA = a.createdAt ?? 0.0;
      final tB = b.createdAt ?? 0.0;
      if (tA != tB) return tA.compareTo(tB);
      return a.id.compareTo(b.id);
    });

    return AccountMonthData(
      openingReal: priorReal,
      openingPred: priorPred,
      transactions: invTxs,
    );
  }

  /// Retorna todos os lançamentos pertencentes à fatura `key` de um cartão de crédito,
  /// independentemente da data de compra (`t.date`).
  List<Transaction> invoiceTransactions(String cardId, String key) {
    final cardAcc = accById(cardId);
    if (cardAcc == null ||
        cardAcc.type != kCardType ||
        cardAcc.card == null) {
      return [];
    }
    final cardCfg = cardAcc.card!;
    rebuildIndexesIfNeeded();
    final cardTxs = _cachedTxsByAccount[cardId] ?? [];
    final list = cardTxs.where((t) {
      if (t.auto == true) return false;
      final ik = t.ik ?? invKeyFor(cardCfg, t.date);
      return ik == key;
    }).toList();
    list.sort((a, b) {
      final dc = a.date.compareTo(b.date);
      if (dc != 0) return dc;
      final tA = a.createdAt ?? 0.0;
      final tB = b.createdAt ?? 0.0;
      if (tA != tB) return tA.compareTo(tB);
      return a.id.compareTo(b.id);
    });
    return list;
  }

  List<CategoryItem> topCategories({String? type}) {
    final list = db.cats
        .where((c) =>
            (c.parent == null || c.parent!.isEmpty) &&
            (type == null || c.type == type))
        .toList();
    list.sort((a, b) => cmpPt(a.name, b.name));
    return list;
  }

  List<CategoryItem> subCategories(String parent, {String? type}) {
    final list = db.cats
        .where((c) => c.parent == parent && (type == null || c.type == type))
        .toList();
    list.sort((a, b) => cmpPt(a.name, b.name));
    return list;
  }

  List<String> allCategoryPaths(String type) {
    final result = <String>[];
    for (final top in topCategories(type: type)) {
      result.add(top.path);
      for (final sub in subCategories(top.name, type: type)) {
        result.add(sub.path);
      }
    }
    return result;
  }

  List<({String label, String value})> allCategoryOptions(String type) {
    final result = <({String label, String value})>[];
    for (final top in topCategories(type: type)) {
      result.add((label: top.name, value: top.path));
      for (final sub in subCategories(top.name, type: type)) {
        result.add((label: '   ↳ ${sub.name}', value: sub.path));
      }
    }
    return result;
  }

  // MARK: - Account Actions

  String? saveAccount({
    String? editingId,
    required String name,
    required String type,
    required int openingCents,
    required int closeDay,
    required int dueDay,
    required String payAccId,
    bool inactive = false,
    bool favorite = false,
    String? business,
    String? bankCode,
    String? agency,
    String? accountNumber,
    String? comments,
    int? minBalance,
    String? logo,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Informe o nome da conta.';

    final trimmedBiz = business?.trim();
    final cleanBiz =
        (trimmedBiz != null && trimmedBiz.isNotEmpty) ? trimmedBiz : null;

    final cleanLogo = (logo != null && logo.trim().isNotEmpty) ? logo.trim() : null;

    CardConfig? cardCfg;
    if (type == kCardType) {
      final cd = closeDay.clamp(1, 31);
      final dd = dueDay.clamp(1, 31);
      if (payAccId.isEmpty) {
        return 'Selecione a conta que pagará a fatura.';
      }
      cardCfg = CardConfig(closeDay: cd, dueDay: dd, pay: payAccId);
    }

    if (editingId != null) {
      final idx = db.accounts.indexWhere((a) => a.id == editingId);
      if (idx != -1) {
        final oldName = db.accounts[idx].name;
        db.accounts[idx].name = trimmed;
        db.accounts[idx].type = type;
        db.accounts[idx].opening = type == kCardType ? 0 : openingCents;
        db.accounts[idx].card = cardCfg;
        db.accounts[idx].inactive = inactive ? true : null;
        db.accounts[idx].favorite = favorite ? true : null;
        db.accounts[idx].business = cleanBiz;
        db.accounts[idx].bankCode = bankCode?.trim().isEmpty == true ? null : bankCode?.trim();
        db.accounts[idx].agency = agency?.trim().isEmpty == true ? null : agency?.trim();
        db.accounts[idx].accountNumber = accountNumber?.trim().isEmpty == true ? null : accountNumber?.trim();
        db.accounts[idx].comments = comments?.trim().isEmpty == true ? null : comments?.trim();
        db.accounts[idx].minBalance = minBalance;
        db.accounts[idx].logo = cleanLogo;
        if (type == kCardType && db.accounts[idx].invoices == null) {
          db.accounts[idx].invoices = {};
        }
        AuditLogManager.instance.logAsync(
          dbPath: dbPath,
          action: AuditAction.update,
          entity: AuditEntity.account,
          id: editingId,
          summary: 'Conta atualizada: "$trimmed" (tipo: $type, anterior: "$oldName")',
        );
      }
    } else {
      final newId = uid();
      final acc = Account(
        id: newId,
        name: trimmed,
        type: type,
        opening: type == kCardType ? 0 : openingCents,
        card: cardCfg,
        invoices: type == kCardType ? {} : null,
        inactive: inactive ? true : null,
        favorite: favorite ? true : null,
        business: cleanBiz,
        bankCode: bankCode?.trim().isEmpty == true ? null : bankCode?.trim(),
        agency: agency?.trim().isEmpty == true ? null : agency?.trim(),
        accountNumber: accountNumber?.trim().isEmpty == true ? null : accountNumber?.trim(),
        comments: comments?.trim().isEmpty == true ? null : comments?.trim(),
        minBalance: minBalance,
        logo: cleanLogo,
      );
      db.accounts.add(acc);
      selectedAccountId = newId;
      activeModule = NavModule.account;
      AuditLogManager.instance.logAsync(
        dbPath: dbPath,
        action: AuditAction.create,
        entity: AuditEntity.account,
        id: newId,
        summary: 'Nova conta cadastrada: "$trimmed" (tipo: $type, saldo inicial: ${brl(openingCents)})',
      );
    }

    syncCards();
    markIndexesDirty();
    save();
    return null;
  }

  void toggleAccountInactive(String id) {
    final idx = db.accounts.indexWhere((a) => a.id == id);
    if (idx == -1) return;
    db.accounts[idx].inactive = !db.accounts[idx].isInactive ? true : null;
    syncCards();
    markIndexesDirty();
    save();
  }

  void toggleAccountFavorite(String id) {
    final idx = db.accounts.indexWhere((a) => a.id == id);
    if (idx == -1) return;
    db.accounts[idx].favorite = !db.accounts[idx].isFavorite ? true : null;
    markIndexesDirty();
    save();
  }

  void moveAccountWithinGroup(List<Account> group, int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= group.length) return;
    if (newIndex < 0 || newIndex >= group.length) return;
    if (oldIndex == newIndex) return;

    final movedAcc = group[oldIndex];
    final targetAcc = group[newIndex];

    final fromGlobalIdx = db.accounts.indexWhere((a) => a.id == movedAcc.id);
    if (fromGlobalIdx == -1) return;

    final item = db.accounts.removeAt(fromGlobalIdx);
    final toGlobalIdx = db.accounts.indexWhere((a) => a.id == targetAcc.id);
    if (toGlobalIdx == -1) {
      db.accounts.insert(fromGlobalIdx, item);
      return;
    }

    final insertIdx = oldIndex < newIndex ? toGlobalIdx + 1 : toGlobalIdx;
    db.accounts.insert(insertIdx, item);
    markIndexesDirty();
    save();
  }

  void moveAccountStepWithinGroup(List<Account> group, String id, int delta) {
    final idx = group.indexWhere((a) => a.id == id);
    if (idx == -1) return;
    final newIdx = idx + delta;
    if (newIdx < 0 || newIdx >= group.length) return;
    moveAccountWithinGroup(group, idx, newIdx);
  }

  void moveAccount(String draggedId, String targetId) {
    if (draggedId == targetId) return;
    final fromIdx = db.accounts.indexWhere((a) => a.id == draggedId);
    final toIdx = db.accounts.indexWhere((a) => a.id == targetId);
    if (fromIdx == -1 || toIdx == -1) return;

    final item = db.accounts.removeAt(fromIdx);
    final newToIdx = db.accounts.indexWhere((a) => a.id == targetId);
    final insertIdx = fromIdx < toIdx ? newToIdx + 1 : newToIdx;
    db.accounts.insert(insertIdx, item);
    markIndexesDirty();
    save();
  }

  int transactionCount(String accountId) {
    rebuildIndexesIfNeeded();
    return (_cachedTxsByAccount[accountId] ?? []).length;
  }

  bool deleteAccount(String id) {
    if (db.accounts.length <= 1) return false;
    if (transactionCount(id) > 0) return false;
    final acc = accById(id);
    final accName = acc?.name ?? id;
    db.accounts.removeWhere((a) => a.id == id);
    db.recs.removeWhere((r) => r.acc == id || r.peer == id);
    syncCards();
    if (db.accounts.isNotEmpty) {
      selectedAccountId = db.accounts.first.id;
    }
    markIndexesDirty();
    save();
    AuditLogManager.instance.logAsync(
      dbPath: dbPath,
      action: AuditAction.delete,
      entity: AuditEntity.account,
      id: id,
      summary: 'Conta excluída: "$accName"',
    );
    return true;
  }

  // MARK: - Payee Suggestions

  List<PayeeSuggestion> payeeSuggestions(String query, {int limit = 6}) {
    final cleanQ = query.trim();
    if (cleanQ.isEmpty) return [];
    rebuildIndexesIfNeeded();
    final qFolded = removeDiacritics(cleanQ).toLowerCase();

    final prefixMatches = <PayeeSuggestion>[];
    final containsMatches = <PayeeSuggestion>[];

    for (final v in _cachedPayeeSuggestions.values) {
      final nameFolded = removeDiacritics(v.name).toLowerCase();
      if (nameFolded == qFolded) continue;
      if (nameFolded.startsWith(qFolded)) {
        prefixMatches.add(
          PayeeSuggestion(
            name: v.name,
            category: v.cat,
            isExpense: v.isExpense,
            count: v.count,
            lastDate: v.lastDate,
          ),
        );
      } else if (nameFolded.contains(qFolded)) {
        containsMatches.add(
          PayeeSuggestion(
            name: v.name,
            category: v.cat,
            isExpense: v.isExpense,
            count: v.count,
            lastDate: v.lastDate,
          ),
        );
      }
    }

    int sortFn(PayeeSuggestion a, PayeeSuggestion b) {
      if (a.count != b.count) return b.count.compareTo(a.count);
      return b.lastDate.compareTo(a.lastDate);
    }

    prefixMatches.sort(sortFn);
    containsMatches.sort(sortFn);

    final combined = [...prefixMatches, ...containsMatches];
    return combined.length > limit ? combined.sublist(0, limit) : combined;
  }

  ({String category, bool isExpense})? lastCategoryAndType(String payee) {
    final cleanQ = payee.trim().toLowerCase();
    if (cleanQ.isEmpty) return null;
    rebuildIndexesIfNeeded();
    final v = _cachedPayeeSuggestions[cleanQ];
    if (v != null && v.cat.isNotEmpty) {
      return (category: v.cat, isExpense: v.isExpense);
    }
    return null;
  }

  // MARK: - Transaction Actions

  void addTransaction({
    required String accId,
    required String date,
    required String payee,
    required String catSelection,
    required String memo,
    required int signedAmt,
    String mode = 'single', // 'single', 'installment', 'recurring'
    String freq = 'monthly',
    int installments = 2,
    String? endDate,
    String? customIk,
  }) {
    final isXfer = catSelection.startsWith('xfer:');
    final peerId = isXfer ? catSelection.substring(5) : null;
    final peerAcc = accById(peerId);
    final curAcc = accById(accId);
    final catLabel =
        isXfer ? 'Transferência: ${peerAcc?.name ?? ""}' : catSelection;
    final count = mode == 'installment' ? installments.clamp(2, 120) : 1;

    final isCard = curAcc?.type == kCardType && curAcc?.card != null;
    final cardCfg = curAcc?.card;
    String? baseIk;
    if (customIk != null && customIk.isNotEmpty) {
      baseIk = customIk;
    } else if (isCard && cardCfg != null) {
      baseIk = invKeyFor(cardCfg, date);
    }

    final today = todayISO();

    if (mode == 'recurring') {
      final rule = RecurrenceRule(
        id: uid(),
        acc: accId,
        peer: isXfer ? peerId : null,
        start: date,
        freq: freq,
        payee: payee,
        cat: catLabel,
        memo: memo,
        amt: isXfer ? -signedAmt.abs() : signedAmt,
        nextSeq: 1,
        end: endDate,
      );
      db.recs.add(rule);
      _month = date.substring(0, 7);
      syncRecs();
    } else if (count > 1 && !isXfer) {
      final pid = uid();
      final parts = splitAmt(signedAmt, count);
      for (int i = 0; i < count; i++) {
        final d = addMonthsDate(date, i);
        final ik = baseIk != null ? addMonthsYM(baseIk, i) : null;
        db.txs.add(
          Transaction(
            id: uid(),
            acc: accId,
            date: d,
            payee: '$payee (${i + 1}/$count)',
            cat: catLabel,
            memo: memo,
            amt: parts[i],
            rec: d.compareTo(today) <= 0 && i == 0,
            ik: ik,
            plan: pid,
            pn: i + 1,
            pt: count,
          ),
        );
      }
      _month = date.substring(0, 7);
    } else {
      final xid = isXfer ? uid() : null;
      final rec = date.compareTo(today) <= 0;
      db.txs.add(
        Transaction(
          id: uid(),
          acc: accId,
          peer: peerId,
          date: date,
          payee: payee,
          cat: catLabel,
          memo: memo,
          amt: signedAmt,
          rec: rec,
          xfer: xid,
          ik: baseIk,
        ),
      );
      if (isXfer && peerId != null) {
        final peerIsCard = peerAcc?.type == kCardType && peerAcc?.card != null;
        String? peerIk;
        if (customIk != null && customIk.isNotEmpty) {
          peerIk = customIk;
        } else if (peerIsCard && peerAcc?.card != null) {
          peerIk = invKeyFor(peerAcc!.card!, date);
        }
        db.txs.add(
          Transaction(
            id: uid(),
            acc: peerId,
            peer: accId,
            date: date,
            payee: payee,
            cat: 'Transferência: ${curAcc?.name ?? ""}',
            memo: memo,
            amt: -signedAmt,
            rec: rec,
            xfer: xid,
            ik: peerIk,
          ),
        );
      }
      _month = date.substring(0, 7);
    }

    syncCards();
    markIndexesDirty();
    save();

    final accName = curAcc?.name ?? accId;
    final typeLabel = isXfer ? 'Transferência' : (signedAmt < 0 ? 'Despesa' : 'Receita');
    final desc = mode == 'installment'
        ? '$typeLabel parcelado ($count x): "$payee" em $accName, total: ${brl(signedAmt)}'
        : '$typeLabel: "$payee" em $accName, ${brl(signedAmt)} ($catLabel)';
    AuditLogManager.instance.logAsync(
      dbPath: dbPath,
      action: AuditAction.create,
      entity: AuditEntity.transaction,
      summary: desc,
    );
  }

  void payInvoice({
    required String cardId,
    required String invoiceKey,
    required int amountCents,
    required String paymentDate,
    required String sourceAccountId,
    String memo = '',
  }) {
    final cardAcc = accById(cardId);
    if (cardAcc == null || cardAcc.type != kCardType) return;
    final sourceAcc = accById(sourceAccountId);
    final cardName = cardAcc.name;
    final sourceName = sourceAcc?.name ?? '';
    final defaultMemo =
        memo.isEmpty ? 'Pagamento da Fatura ${fmtMonth(invoiceKey)}' : memo;

    final xid = uid();
    final rec = paymentDate.compareTo(todayISO()) <= 0;

    db.txs.add(
      Transaction(
        id: uid(),
        acc: sourceAccountId,
        peer: cardId,
        date: paymentDate,
        payee: 'Pagamento de Fatura: $cardName',
        cat: 'Transferência: $cardName',
        memo: defaultMemo,
        amt: -amountCents.abs(),
        rec: rec,
        xfer: xid,
      ),
    );

    db.txs.add(
      Transaction(
        id: uid(),
        acc: cardId,
        peer: sourceAccountId,
        date: paymentDate,
        payee:
            'Pagamento de Fatura${sourceName.isEmpty ? "" : " ($sourceName)"}',
        cat: 'Transferência: $sourceName',
        memo: defaultMemo,
        amt: amountCents.abs(),
        rec: rec,
        xfer: xid,
        ik: invoiceKey,
      ),
    );

    syncCards();
    markIndexesDirty();
    save();
  }

  void toggleReconciled(String txId) {
    final idx = db.txs.indexWhere((t) => t.id == txId);
    if (idx == -1) return;
    db.txs[idx].rec = !db.txs[idx].rec;
    final newRec = db.txs[idx].rec;
    final xfer = db.txs[idx].xfer;
    if (xfer != null) {
      for (int i = 0; i < db.txs.length; i++) {
        if (db.txs[i].xfer == xfer) {
          db.txs[i].rec = newRec;
        }
      }
    }
    markIndexesDirty();
    save();
  }

  void updateTransaction({
    required String txId,
    String? newAccId,
    required String newDate,
    required String newPayee,
    required String newCatSelection,
    required String newMemo,
    required int newSignedAmt,
    ScopeChoice scope = ScopeChoice.only,
    String? newIk,
  }) {
    final idx = db.txs.indexWhere((t) => t.id == txId);
    if (idx == -1) return;
    final t = db.txs[idx];

    if (t.auto == true ||
        (t.xfer != null && t.xfer!.startsWith('invpay:'))) {
      if (t.card != null && t.inv != null) {
        final cIdx = db.accounts.indexWhere((a) => a.id == t.card);
        if (cIdx != -1) {
          final inv = db.accounts[cIdx].invoices?[t.inv!];
          if (inv != null) {
            inv.due = newDate;
            if (newAccId != null &&
                newAccId != t.acc &&
                t.acc != t.card) {
              inv.pay = newAccId;
            }
            inv.manual = true;
          }
        }
      }
      syncCards();
      markIndexesDirty();
      save();
      return;
    }

    final oldAccId = t.acc;
    final targetAccId = newAccId ?? oldAccId;
    final accChanged = targetAccId != oldAccId;

    final cleanPayee =
        newPayee.replaceAll(RegExp(r'\s*\(\d+\/\d+\)$'), '').trim();
    final isXfer = newCatSelection.startsWith('xfer:');
    final String newCat;
    if (isXfer) {
      final pId = newCatSelection.substring(5);
      newCat = 'Transferência: ${accById(pId)?.name ?? ""}';
    } else if (t.xfer != null) {
      newCat = t.cat;
    } else {
      newCat = newCatSelection;
    }

    final oldDate = t.date;
    db.txs[idx].acc = targetAccId;
    db.txs[idx].date = newDate;
    db.txs[idx].memo = newMemo;
    db.txs[idx].amt = newSignedAmt;

    final cAcc = accById(targetAccId);
    if (cAcc != null && cAcc.type == kCardType && cAcc.card != null) {
      if (newIk != null && newIk.isNotEmpty) {
        db.txs[idx].ik = newIk;
      } else if (accChanged || (newDate != oldDate && db.txs[idx].ik == null)) {
        db.txs[idx].ik = invKeyFor(cAcc.card!, newDate);
      }
    } else {
      db.txs[idx].ik = null;
    }

    if (t.xfer != null) {
      final xfer = t.xfer!;
      db.txs[idx].payee = newPayee;
      for (int i = 0; i < db.txs.length; i++) {
        if (db.txs[i].xfer == xfer && db.txs[i].id != t.id) {
          db.txs[i].date = newDate;
          db.txs[i].payee = newPayee;
          db.txs[i].memo = newMemo;
          db.txs[i].amt = -newSignedAmt;
          if (accChanged) {
            db.txs[i].peer = targetAccId;
            db.txs[i].cat =
                'Transferência: ${accById(targetAccId)?.name ?? ""}';
          }
          final peerAcc = accById(db.txs[i].acc);
          if (peerAcc != null &&
              peerAcc.type == kCardType &&
              peerAcc.card != null) {
            if (newIk != null && newIk.isNotEmpty) {
              db.txs[i].ik = newIk;
            } else if (newDate != oldDate && db.txs[i].ik == null) {
              db.txs[i].ik = invKeyFor(peerAcc.card!, newDate);
            }
          }
        }
      }
    }

    if (scope == ScopeChoice.forward && t.recId != null && t.recSeq != null) {
      final recId = t.recId!;
      final baseSeq = t.recSeq!;
      final dateChanged = newDate != oldDate;
      db.txs[idx].payee = cleanPayee;
      db.txs[idx].cat = newCat;

      final rIdx = db.recs.indexWhere((r) => r.id == recId);
      if (rIdx != -1) {
        final freq = db.recs[rIdx].freq;
        if (accChanged) db.recs[rIdx].acc = targetAccId;
        db.recs[rIdx].payee = cleanPayee;
        db.recs[rIdx].cat = newCat;
        db.recs[rIdx].memo = newMemo;
        db.recs[rIdx].amt = newSignedAmt;
        if (dateChanged) {
          db.recs[rIdx].start = addFreqDate(newDate, freq, -(baseSeq - 1));
        }
      }

      final freq = (rIdx != -1 ? db.recs[rIdx].freq : t.recFreq) ?? 'monthly';
      final targetAccName = accById(targetAccId)?.name ?? '';
      for (int i = 0; i < db.txs.length; i++) {
        if (db.txs[i].recId == recId &&
            db.txs[i].id != t.id &&
            (db.txs[i].recSeq ?? 0) > baseSeq &&
            !db.txs[i].rec) {
          final isPeer = db.txs[i].peer != null &&
              db.txs[i].acc != targetAccId &&
              (t.peer == db.txs[i].acc || t.acc == db.txs[i].acc);
          if (isPeer) {
            db.txs[i].payee = cleanPayee;
            db.txs[i].memo = newMemo;
            db.txs[i].amt = -newSignedAmt;
            if (accChanged) {
              db.txs[i].peer = targetAccId;
              db.txs[i].cat = 'Transferência: $targetAccName';
            }
          } else {
            if (accChanged) db.txs[i].acc = targetAccId;
            db.txs[i].payee = cleanPayee;
            db.txs[i].cat = newCat;
            db.txs[i].memo = newMemo;
            db.txs[i].amt = newSignedAmt;
          }
          if (dateChanged && db.txs[i].recSeq != null) {
            final step = db.txs[i].recSeq! - baseSeq;
            db.txs[i].date = addFreqDate(newDate, freq, step);
          }
          final itemAcc = accById(db.txs[i].acc);
          if (itemAcc != null &&
              itemAcc.type == kCardType &&
              itemAcc.card != null) {
            db.txs[i].ik = invKeyFor(itemAcc.card!, db.txs[i].date);
          } else {
            db.txs[i].ik = null;
          }
        }
      }
    } else if (scope == ScopeChoice.forward &&
        t.plan != null &&
        t.pn != null) {
      final plan = t.plan!;
      final basePn = t.pn!;
      final dateChanged = newDate != oldDate;
      final pt = t.pt ?? 1;
      db.txs[idx].payee = '$cleanPayee ($basePn/$pt)';
      db.txs[idx].cat = newCat;

      for (int i = 0; i < db.txs.length; i++) {
        if (db.txs[i].plan == plan &&
            db.txs[i].id != t.id &&
            (db.txs[i].pn ?? 0) > basePn &&
            !db.txs[i].rec) {
          if (accChanged) db.txs[i].acc = targetAccId;
          final opn = db.txs[i].pn ?? 1;
          final opt = db.txs[i].pt ?? pt;
          db.txs[i].payee = '$cleanPayee ($opn/$opt)';
          db.txs[i].cat = newCat;
          db.txs[i].memo = newMemo;
          db.txs[i].amt = newSignedAmt;
          if (dateChanged) {
            final step = opn - basePn;
            db.txs[i].date = addMonthsDate(newDate, step);
          }
          if (cAcc != null && cAcc.type == kCardType && cAcc.card != null) {
            final step = opn - basePn;
            final base =
                newIk ?? db.txs[idx].ik ?? invKeyFor(cAcc.card!, newDate);
            db.txs[i].ik = addMonthsYM(base, step);
          } else {
            db.txs[i].ik = null;
          }
        }
      }
    } else if (t.xfer == null) {
      if (t.pn != null && t.pt != null && t.plan != null) {
        db.txs[idx].payee = '$cleanPayee (${t.pn}/${t.pt})';
      } else {
        db.txs[idx].payee = newPayee;
      }
      db.txs[idx].cat = newCat;
    }

    syncRecs();
    syncCards();
    markIndexesDirty();
    save();

    final accName = accById(newAccId ?? t.acc)?.name ?? t.acc;
    AuditLogManager.instance.logAsync(
      dbPath: dbPath,
      action: AuditAction.update,
      entity: AuditEntity.transaction,
      id: txId,
      summary: 'Lançamento alterado: "$newPayee" em $accName, ${brl(newSignedAmt)} ($newCatSelection)',
    );
  }

  void deleteTransaction(String txId, ScopeChoice scope) {
    final idx = db.txs.indexWhere((t) => t.id == txId);
    if (idx == -1) return;
    final t = db.txs[idx];
    if (t.auto == true) return;

    if (t.recId != null) {
      final recId = t.recId!;
      if (scope == ScopeChoice.all) {
        db.recs.removeWhere((r) => r.id == recId);
        db.txs.removeWhere((x) =>
            x.recId == recId &&
            (!x.rec || x.id == t.id || (t.xfer != null && x.xfer == t.xfer)));
      } else if (scope == ScopeChoice.forward && t.recSeq != null) {
        final seq = t.recSeq!;
        final rIdx = db.recs.indexWhere((r) => r.id == recId);
        if (rIdx != -1) {
          db.recs[rIdx].end = addDaysDate(t.date, -1);
        }
        db.txs.removeWhere((x) =>
            x.recId == recId &&
            (x.recSeq ?? 0) >= seq &&
            (!x.rec || x.id == t.id || (t.xfer != null && x.xfer == t.xfer)));
      } else {
        if (t.xfer != null) {
          db.txs.removeWhere((x) => x.xfer == t.xfer);
        } else {
          db.txs.removeWhere((x) => x.id == t.id);
        }
      }
    } else if (t.plan != null) {
      final plan = t.plan!;
      if (scope == ScopeChoice.all) {
        db.txs.removeWhere((x) => x.plan == plan && (!x.rec || x.id == t.id));
      } else if (scope == ScopeChoice.forward && t.pn != null) {
        final pn = t.pn!;
        db.txs.removeWhere((x) =>
            x.plan == plan && (x.pn ?? 0) >= pn && (!x.rec || x.id == t.id));
      } else {
        db.txs.removeWhere((x) => x.id == t.id);
      }
    } else if (t.xfer != null) {
      db.txs.removeWhere((x) => x.xfer == t.xfer);
    } else {
      db.txs.removeWhere((x) => x.id == t.id);
    }

    syncCards();
    markIndexesDirty();
    save();

    final accName = accById(t.acc)?.name ?? t.acc;
    final scopeLabel = scope == ScopeChoice.all
        ? ' (todos do plano/recorrência)'
        : (scope == ScopeChoice.forward ? ' (este e futuros)' : '');
    AuditLogManager.instance.logAsync(
      dbPath: dbPath,
      action: AuditAction.delete,
      entity: AuditEntity.transaction,
      id: txId,
      summary: 'Lançamento excluído: "${t.payee}" em $accName, ${brl(t.amt)}$scopeLabel',
    );
  }

  BatchDeletePreview previewBatchDelete({
    String? accountId,
    required bool isAllTime,
    required String startDate,
    required String endDate,
    bool deleteTransferCounterparts = true,
  }) {
    final matchingIds = <String>{};
    final transferKeys = <String>{};

    final cleanStart =
        startDate.compareTo(endDate) <= 0 ? startDate : endDate;
    final cleanEnd = startDate.compareTo(endDate) <= 0 ? endDate : startDate;

    for (final tx in db.txs) {
      if (tx.auto == true) continue;
      final accMatches =
          (accountId == null || accountId.isEmpty) || (tx.acc == accountId);
      final dateMatches = isAllTime ||
          (tx.date.compareTo(cleanStart) >= 0 &&
              tx.date.compareTo(cleanEnd) <= 0);
      if (accMatches && dateMatches) {
        matchingIds.add(tx.id);
        if (deleteTransferCounterparts && tx.xfer != null) {
          transferKeys.add(tx.xfer!);
        }
      }
    }

    if (deleteTransferCounterparts && transferKeys.isNotEmpty) {
      for (final tx in db.txs) {
        if (tx.auto == true) continue;
        if (tx.xfer != null && transferKeys.contains(tx.xfer!)) {
          matchingIds.add(tx.id);
        }
      }
    }

    int income = 0;
    int expense = 0;
    final accSet = <String>{};

    for (final tx in db.txs) {
      if (matchingIds.contains(tx.id)) {
        accSet.add(tx.acc);
        if (tx.amt > 0) {
          income += tx.amt;
        } else {
          expense += tx.amt;
        }
      }
    }

    return BatchDeletePreview(
      count: matchingIds.length,
      incomeCents: income,
      expenseCents: expense,
      netCents: income + expense,
      affectedAccountsCount: accSet.length,
    );
  }

  int executeBatchDelete({
    String? accountId,
    required bool isAllTime,
    required String startDate,
    required String endDate,
    bool deleteTransferCounterparts = true,
  }) {
    final matchingIds = <String>{};
    final transferKeys = <String>{};

    final cleanStart =
        startDate.compareTo(endDate) <= 0 ? startDate : endDate;
    final cleanEnd = startDate.compareTo(endDate) <= 0 ? endDate : startDate;

    for (final tx in db.txs) {
      if (tx.auto == true) continue;
      final accMatches =
          (accountId == null || accountId.isEmpty) || (tx.acc == accountId);
      final dateMatches = isAllTime ||
          (tx.date.compareTo(cleanStart) >= 0 &&
              tx.date.compareTo(cleanEnd) <= 0);
      if (accMatches && dateMatches) {
        matchingIds.add(tx.id);
        if (tx.xfer != null) {
          transferKeys.add(tx.xfer!);
        }
      }
    }

    if (deleteTransferCounterparts && transferKeys.isNotEmpty) {
      for (final tx in db.txs) {
        if (tx.auto == true) continue;
        if (tx.xfer != null && transferKeys.contains(tx.xfer!)) {
          matchingIds.add(tx.id);
        }
      }
    } else if (!deleteTransferCounterparts && transferKeys.isNotEmpty) {
      for (int i = 0; i < db.txs.length; i++) {
        if (!matchingIds.contains(db.txs[i].id) &&
            db.txs[i].xfer != null &&
            transferKeys.contains(db.txs[i].xfer!)) {
          db.txs[i].xfer = null;
          db.txs[i].peer = null;
        }
      }
    }

    if (matchingIds.isEmpty) return 0;

    final initialCount = db.txs.length;
    db.txs.removeWhere((t) => matchingIds.contains(t.id));
    final deletedCount = initialCount - db.txs.length;

    syncCards();
    markIndexesDirty();
    rebuildIndexes();
    save(immediate: true);

    AuditLogManager.instance.logAsync(
      dbPath: dbPath,
      action: AuditAction.batchDelete,
      entity: AuditEntity.transaction,
      summary: 'Limpeza em lote: $deletedCount lançamentos excluídos '
          '(Período: ${isAllTime ? "Todo o histórico" : "$cleanStart a $cleanEnd"})',
    );

    return deletedCount;
  }

  // MARK: - Smart Predictions Adjustment

  void setPredMode(String mode) {
    if (db.predMode == mode) return;
    db.predMode = mode;
    save();
    notifyListeners();
  }

  PredictionsAdjustResult adjustPredictions(String targetMonth) {
    final invoiceMode = db.predMode == 'invoice';
    final months = invoiceMode
        ? [targetMonth, addMonthsYM(targetMonth, 1), addMonthsYM(targetMonth, 2)]
        : [targetMonth];

    // Grupos de abatimento: previsões + lançamentos que as abatem
    final groups = <({String cat, List<Transaction> preds, List<Transaction> spent, String label})>[];
    var allPredCount = 0;
    final cardCfgs = <String, CardConfig>{
      for (final a in db.accounts)
        if (a.card != null) a.id: a.card!,
    };

    for (final m in months) {
      final monthTxs =
          db.txs.where((t) => t.date.startsWith(m) && t.auto != true).toList();
      final predTxs =
          monthTxs.where((t) => isPredictionPayee(t.payee)).toList();
      allPredCount += predTxs.length;

      final monthPreds = <String, List<Transaction>>{};
      final invPreds = <String, List<Transaction>>{};
      for (final pt in predTxs) {
        final cfg = cardCfgs[pt.acc];
        if (invoiceMode && cfg != null) {
          final pik = pt.ik ?? invKeyFor(cfg, pt.date);
          invPreds.putIfAbsent('${pt.cat}|$pik', () => []).add(pt);
        } else {
          monthPreds.putIfAbsent(pt.cat, () => []).add(pt);
        }
      }
      monthPreds.forEach((cat, preds) {
        final spent = monthTxs
            .where((t) =>
                t.cat == cat && !isPredictionPayee(t.payee) && t.xfer == null)
            .toList();
        groups.add((cat: cat, preds: preds, spent: spent, label: ''));
      });
      invPreds.forEach((key, preds) {
        final idx = key.lastIndexOf('|');
        final cat = key.substring(0, idx);
        final pik = key.substring(idx + 1);
        // Somente lançamentos de cartão cuja fatura (ik) é a mesma da previsão
        final spent = db.txs.where((t) {
          final cfg = cardCfgs[t.acc];
          if (cfg == null) return false;
          if (t.auto == true || t.cat != cat || t.xfer != null) return false;
          if (isPredictionPayee(t.payee)) return false;
          return (t.ik ?? invKeyFor(cfg, t.date)) == pik;
        }).toList();
        groups.add((
          cat: cat,
          preds: preds,
          spent: spent,
          label: ' • Fatura ${fmtMonth(pik)}'
        ));
      });
    }

    if (allPredCount == 0) {
      final res = PredictionsAdjustResult(
        title: 'Ajustar Previsões',
        message:
            'Nenhum lançamento com descrição iniciando por "Previsão" foi encontrado em ${fmtMonth(targetMonth)}.',
        hasExhausted: false,
        items: const [],
        month: targetMonth,
        totalDeductedCents: 0,
      );
      lastPredictionsResult = res;
      notifyListeners();
      return res;
    }

    final adjustedItems = <String>[];
    final exhaustedItems = <String>[];
    final unchangedItems = <String>[];
    final detailedItems = <PredictionAdjustItem>[];
    int totalDeductedCents = 0;
    final idsToDelete = <String>{};

    for (final group in groups) {
      final cat = group.cat;
      final catPreds = group.preds;
      final otherTxs = group.spent;

      int netSpent = 0;
      for (final ot in otherTxs) {
        if (ot.amt < 0) {
          netSpent += ot.amt.abs();
        } else if (ot.amt > 0) {
          netSpent -= ot.amt;
        }
      }
      if (netSpent < 0) netSpent = 0;

      int remainingExpensesToAbate = netSpent;

      for (final pred in catPreds) {
        final idx = db.txs.indexWhere((t) => t.id == pred.id);
        if (idx == -1) continue;
        final base = parseBaseFromMemo(pred.memo) ?? pred.amt.abs();
        final deduction =
            base < remainingExpensesToAbate ? base : remainingExpensesToAbate;
        final newRemaining = base - deduction;
        remainingExpensesToAbate -= deduction;
        totalDeductedCents += deduction;

        final accName = accById(pred.acc)?.name ?? 'Conta';
        final catLabel =
            (cat.isEmpty ? 'Sem categoria' : cat) + group.label;

        if (newRemaining > 0) {
          final sign = pred.amt < 0 ? -1 : 1;
          final newSigned = sign * newRemaining;
          final newMemo = memoWithBaseTag(pred.memo, base);
          final wasChanged =
              (db.txs[idx].amt != newSigned || db.txs[idx].memo != newMemo);

          db.txs[idx].amt = newSigned;
          db.txs[idx].memo = newMemo;

          if (wasChanged) {
            adjustedItems.add(
              '• ${pred.payee} ($accName • $catLabel):\n  Ajustada para ${brl(newRemaining)} (Base original: ${brl(base)} − Gastos da categoria: ${brl(netSpent)})',
            );
            detailedItems.add(
              PredictionAdjustItem(
                payee: pred.payee,
                accountName: accName,
                category: catLabel,
                baseCents: base,
                spentCents: netSpent,
                remainingCents: newRemaining,
                status: PredictionAdjustStatus.adjusted,
              ),
            );
          } else {
            unchangedItems.add(
              '• ${pred.payee} ($accName • $catLabel):\n  Mantida em ${brl(newRemaining)} (Base: ${brl(base)} − Gastos: ${brl(netSpent)})',
            );
            detailedItems.add(
              PredictionAdjustItem(
                payee: pred.payee,
                accountName: accName,
                category: catLabel,
                baseCents: base,
                spentCents: netSpent,
                remainingCents: newRemaining,
                status: PredictionAdjustStatus.unchanged,
              ),
            );
          }
        } else {
          idsToDelete.add(pred.id);
          exhaustedItems.add(
            '• ${pred.payee} ($accName • $catLabel):\n  Excluída — Previsão esgotada! Não há mais previsão disponível (Base: ${brl(base)} atingida por ${brl(netSpent)} em gastos).',
          );
          detailedItems.add(
            PredictionAdjustItem(
              payee: pred.payee,
              accountName: accName,
              category: catLabel,
              baseCents: base,
              spentCents: netSpent,
              remainingCents: 0,
              status: PredictionAdjustStatus.exhausted,
            ),
          );
        }
      }
    }

    if (idsToDelete.isNotEmpty) {
      db.txs.removeWhere((t) => idsToDelete.contains(t.id));
    }

    syncCards();
    markIndexesDirty();
    rebuildIndexes();
    save(immediate: true);

    final sections = <String>[];
    if (exhaustedItems.isNotEmpty) {
      sections.add(
        '⚠️ PREVISÃO NÃO MAIS DISPONÍVEL (EXCLUÍDA):\n${exhaustedItems.join("\n\n")}',
      );
    }
    if (adjustedItems.isNotEmpty) {
      sections.add('✓ PREVISÕES AJUSTADAS:\n${adjustedItems.join("\n\n")}');
    }
    if (unchangedItems.isNotEmpty &&
        adjustedItems.isEmpty &&
        exhaustedItems.isEmpty) {
      sections.add(
        'ℹ️ PREVISÕES JÁ ATUALIZADAS:\n${unchangedItems.join("\n\n")}',
      );
    }

    final String title;
    if (exhaustedItems.isNotEmpty) {
      title = 'Ajuste de Previsões — Previsão Esgotada';
    } else if (adjustedItems.isNotEmpty) {
      title = 'Previsões Ajustadas com Sucesso';
    } else {
      title = 'Previsões em Dia';
    }

    final result = PredictionsAdjustResult(
      title: title,
      message: sections.join('\n\n'),
      hasExhausted: exhaustedItems.isNotEmpty,
      items: detailedItems,
      month: targetMonth,
      totalDeductedCents: totalDeductedCents,
    );
    lastPredictionsResult = result;
    notifyListeners();
    return result;
  }

  // MARK: - Category & Budget Actions

  String? saveCategory({
    String? editingPath,
    required String name,
    String? parent,
    required String type,
    bool includeInReports = true,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Informe o nome da categoria.';
    if (trimmed.contains(kCategorySep)) {
      return 'O nome não pode conter "$kCategorySep".';
    }

    final cleanParent = (parent != null && parent.isEmpty) ? null : parent;
    final newItem = CategoryItem(
      name: trimmed,
      parent: cleanParent,
      type: type,
      includeInReports: includeInReports,
    );
    final newPath = newItem.path;

    if (db.cats.any((c) =>
        c.path.toLowerCase() == newPath.toLowerCase() &&
        c.path != editingPath)) {
      return 'Essa categoria já existe.';
    }

    if (editingPath != null) {
      final idx = db.cats.indexWhere((c) => c.path == editingPath);
      if (idx != -1) {
        final oldCat = db.cats[idx];
        if (oldCat.parent == null &&
            cleanParent != null &&
            db.cats.any((c) => c.parent == oldCat.name)) {
          return 'Esta categoria possui subcategorias e não pode virar subcategoria.';
        }

        db.cats[idx] = newItem;

        if (oldCat.parent == null) {
          for (int i = 0; i < db.cats.length; i++) {
            if (db.cats[i].parent == oldCat.name) {
              db.cats[i].parent = cleanParent ?? trimmed;
              db.cats[i].type = type;
            }
          }
        }

        if (editingPath != newPath) {
          for (int i = 0; i < db.txs.length; i++) {
            if (db.txs[i].cat == editingPath) {
              db.txs[i].cat = newPath;
            } else if (oldCat.parent == null &&
                db.txs[i].cat.startsWith('${oldCat.name}$kCategorySep')) {
              final suffix = db.txs[i].cat
                  .substring('${oldCat.name}$kCategorySep'.length);
              db.txs[i].cat = '$trimmed$kCategorySep$suffix';
            }
          }
          for (int i = 0; i < db.recs.length; i++) {
            if (db.recs[i].cat == editingPath) {
              db.recs[i].cat = newPath;
            } else if (oldCat.parent == null &&
                db.recs[i].cat.startsWith('${oldCat.name}$kCategorySep')) {
              final suffix = db.recs[i].cat
                  .substring('${oldCat.name}$kCategorySep'.length);
              db.recs[i].cat = '$trimmed$kCategorySep$suffix';
            }
          }
          final bVal = db.budgets.remove(editingPath);
          if (bVal != null) {
            db.budgets[newPath] = bVal;
          }
        }
      }
    } else {
      db.cats.add(newItem);
    }

    db.cats.sort(byCatSort);
    save();

    final actionType = editingPath != null ? AuditAction.update : AuditAction.create;
    final summaryStr = editingPath != null
        ? 'Categoria alterada: "$newPath" (anterior: "$editingPath", tipo: $type)'
        : 'Nova categoria criada: "$newPath" (tipo: $type)';
    AuditLogManager.instance.logAsync(
      dbPath: dbPath,
      action: actionType,
      entity: AuditEntity.category,
      summary: summaryStr,
    );

    return null;
  }

  Set<String> affectedCategoryPaths(String path) {
    final target = db.cats.where((c) => c.path == path).firstOrNull;
    if (target == null) return {path};
    final isTop = target.parent == null || target.parent!.isEmpty;
    return db.cats
        .where((c) => c.path == path || (isTop && c.parent == target.name))
        .map((c) => c.path)
        .toSet();
  }

  int categoryUsageCount(String path) {
    final affected = affectedCategoryPaths(path);
    return db.txs.where((t) => affected.contains(t.cat)).length;
  }

  void deleteCategory(String path, {String replacement = 'Outros'}) {
    final target = db.cats.where((c) => c.path == path).firstOrNull;
    if (target == null) return;
    final affected = affectedCategoryPaths(path);

    final usedInTxs = db.txs.any((t) => affected.contains(t.cat)) ||
        db.recs.any((r) => affected.contains(r.cat));
    if (usedInTxs &&
        replacement.isNotEmpty &&
        !db.cats
            .any((c) => c.path == replacement && !affected.contains(c.path))) {
      final parts = replacement.split(kCategorySep);
      if (parts.length > 1) {
        db.cats.add(
          CategoryItem(
              name: parts[1], parent: parts[0], type: target.type),
        );
      } else {
        db.cats.add(
          CategoryItem(name: replacement, parent: null, type: target.type),
        );
      }
    }

    for (int i = 0; i < db.txs.length; i++) {
      if (affected.contains(db.txs[i].cat)) {
        db.txs[i].cat = replacement;
      }
    }
    for (int i = 0; i < db.recs.length; i++) {
      if (affected.contains(db.recs[i].cat)) {
        db.recs[i].cat = replacement;
      }
    }
    for (final ap in affected) {
      db.budgets.remove(ap);
    }
    db.cats.removeWhere((c) => affected.contains(c.path));
    db.cats.sort(byCatSort);
    save();

    AuditLogManager.instance.logAsync(
      dbPath: dbPath,
      action: AuditAction.delete,
      entity: AuditEntity.category,
      summary: 'Categoria excluída: "$path" (lançamentos movidos para "$replacement")',
    );
  }

  void setBudget(String categoryPath, int cents) {
    if (cents > 0) {
      db.budgets[categoryPath] = cents;
    } else {
      db.budgets.remove(categoryPath);
    }
    save();
  }

  bool isCategoryIncludedInReports(String catPath) {
    for (final cat in db.cats) {
      if (cat.path.toLowerCase() == catPath.toLowerCase()) {
        return cat.effectiveIncludeInReports;
      }
    }
    final parts = catPath.split(kCategorySep);
    if (parts.length > 1) {
      final parentName = parts[0].trim();
      for (final cat in db.cats) {
        if (cat.name.toLowerCase() == parentName.toLowerCase() &&
            cat.parent == null) {
          if (!cat.effectiveIncludeInReports) return false;
        }
      }
    }
    final norm = removeDiacritics(catPath).toLowerCase();
    if (norm.contains('transferencia') || norm.contains('transferencias')) {
      return false;
    }
    return true;
  }

  // MARK: - Monthly Report Builder

  MonthlyReportData buildMonthlyReport(
    String monthYM, {
    Set<String>? accountFilterIds,
  }) {
    final txs = monthTransactions(monthYM).where((tx) {
      if (accountFilterIds != null &&
          accountFilterIds.isNotEmpty &&
          !accountFilterIds.contains(tx.acc)) {
        return false;
      }
      if (tx.xfer != null || tx.peer != null) return false;
      if (!isCategoryIncludedInReports(tx.cat)) return false;
      return true;
    }).toList();

    ({List<CategoryGroupStat> groups, int grandTotal}) buildSection(
        bool positive) {
      final filtered =
          txs.where((t) => positive ? t.amt > 0 : t.amt < 0).toList();
      final map = <String, ({int total, Map<String, int> subs})>{};
      int grand = 0;

      for (final t in filtered) {
        final v = t.amt.abs();
        grand += v;
        final parts =
            t.cat.isEmpty ? ['Sem categoria'] : t.cat.split(kCategorySep);
        final top = parts[0];
        final prev = map[top] ?? (total: 0, subs: <String, int>{});
        final newTotal = prev.total + v;
        final subs = Map<String, int>.from(prev.subs);
        if (parts.length > 1) {
          final sub = parts[1];
          subs[sub] = (subs[sub] ?? 0) + v;
        }
        map[top] = (total: newTotal, subs: subs);
      }

      final groups = map.entries.map((entry) {
        final key = entry.key;
        final val = entry.value;
        final topPct =
            grand > 0 ? ((val.total / grand) * 100.0).round() : 0;
        final subs = val.subs.entries.map((s) {
          final subPct =
              val.total > 0 ? ((s.value / val.total) * 100.0).round() : 0;
          return SubCategoryStat(
            name: s.key,
            amount: s.value,
            percentage: subPct,
          );
        }).toList()
          ..sort((a, b) => b.amount.compareTo(a.amount));

        return CategoryGroupStat(
          name: key,
          total: val.total,
          percentage: topPct,
          subs: subs,
        );
      }).toList()
        ..sort((a, b) => b.total.compareTo(a.total));

      return (groups: groups, grandTotal: grand);
    }

    final inc = buildSection(true);
    final exp = buildSection(false);
    final net = inc.grandTotal - exp.grandTotal;
    final rate = inc.grandTotal > 0
        ? ((net / inc.grandTotal) * 100.0).round()
        : 0;

    return MonthlyReportData(
      monthYM: monthYM,
      incomeGroups: inc.groups,
      expenseGroups: exp.groups,
      totalIncome: inc.grandTotal,
      totalExpense: exp.grandTotal,
      netTotal: net,
      savingsRate: rate,
    );
  }

  // MARK: - Importers & Exporters Integration

  ImportSummary importCSVBytes(
    Uint8List bytes, {
    String? targetAccountId,
    bool allowDuplicates = false,
  }) {
    final content = readTextBytesWithEncoding(bytes);
    final result = CSVImporter.parse(
      content: content,
      targetAccountId: targetAccountId,
      existingAccounts: db.accounts,
      existingCats: db.cats,
      existingTxs: db.txs,
      allowDuplicates: allowDuplicates,
    );

    for (final acc in result.newAccounts) {
      if (!db.accounts.any((a) => a.id == acc.id || cmpPt(a.name, acc.name) == 0)) {
        db.accounts.add(acc);
      }
    }
    for (final cat in result.newCats) {
      if (!db.cats.any((c) => c.path == cat.path)) {
        db.cats.add(cat);
      }
    }
    db.cats.sort(byCatSort);
    db.txs.addAll(result.newTxs);
    migrate();
    syncRecs();
    syncCards(settleCardInvoices: true);
    rebuildIndexes();
    save(immediate: true);

    final summary = ImportSummary(
      title: 'Importação CSV Concluída',
      importedCount: result.newTxs.length,
      skippedCount: result.skippedCount,
      newCategoriesCount: result.newCats.length,
      newAccountsCount: result.newAccounts.length,
    );
    lastImportSummary = summary;
    AuditLogManager.instance.logAsync(
      dbPath: dbPath,
      action: AuditAction.importBatch,
      entity: AuditEntity.transaction,
      summary: 'Importação CSV: ${result.newTxs.length} lançamentos adicionados, '
          '${result.skippedCount} duplicados ignorados',
    );
    notifyListeners();
    return summary;
  }

  ImportSummary importQIFBytes(
    Uint8List bytes, {
    String? targetAccountId,
  }) {
    final content = readTextBytesWithEncoding(bytes);
    final result = QIFImporter.parse(
      content: content,
      targetAccountId: targetAccountId,
      existingAccounts: db.accounts,
      existingCats: db.cats,
      existingTxs: db.txs,
    );

    for (final acc in result.newAccounts) {
      if (!db.accounts.any((a) => a.id == acc.id)) {
        db.accounts.add(acc);
      }
    }
    for (final cat in result.newCats) {
      if (!db.cats.any((c) => c.path == cat.path)) {
        db.cats.add(cat);
      }
    }
    db.cats.sort(byCatSort);
    db.txs.addAll(result.newTxs);
    migrate();
    syncRecs();
    syncCards(settleCardInvoices: true);
    rebuildIndexes();
    save(immediate: true);

    final summary = ImportSummary(
      title: 'Importação QIF Concluída',
      importedCount: result.newTxs.length,
      skippedCount: result.skippedCount,
      newCategoriesCount: result.newCats.length,
      newAccountsCount: result.newAccounts.length,
    );
    lastImportSummary = summary;
    AuditLogManager.instance.logAsync(
      dbPath: dbPath,
      action: AuditAction.importBatch,
      entity: AuditEntity.transaction,
      summary: 'Importação QIF: ${result.newTxs.length} lançamentos adicionados, '
          '${result.skippedCount} ignorados',
    );
    notifyListeners();
    return summary;
  }

  ImportSummary importCategoriesCSVBytes(Uint8List bytes) {
    final content = readTextBytesWithEncoding(bytes);
    final result = CategoryCSVImporter.parse(
      content: content,
      existingCats: db.cats,
    );
    for (final cat in result.newCats) {
      if (!db.cats.any((c) => c.path.toLowerCase() == cat.path.toLowerCase())) {
        db.cats.add(cat);
      }
    }
    db.cats.sort(byCatSort);
    rebuildIndexes();
    save(immediate: true);

    final summary = ImportSummary(
      title: 'Importação de Categorias Concluída',
      importedCount: result.newCats.length,
      skippedCount: result.skippedCount,
      newCategoriesCount: result.newCats.length,
      newAccountsCount: 0,
    );
    lastImportSummary = summary;
    notifyListeners();
    return summary;
  }

  MobileInboxImportResult importMobileInboxBytes(Uint8List bytes) {
    final result = MobileInboxImporter.parse(
      bytes: bytes,
      existingAccounts: db.accounts,
      existingCats: db.cats,
      existingTxs: db.txs,
    );

    for (final cat in result.newCats) {
      if (!db.cats.any((c) => c.path.toLowerCase() == cat.path.toLowerCase())) {
        db.cats.add(cat);
      }
    }
    if (result.newCats.isNotEmpty) {
      db.cats.sort(byCatSort);
    }

    db.txs.addAll(result.newTxs);
    migrate();
    syncRecs();
    syncCards(settleCardInvoices: true);
    rebuildIndexes();
    save(immediate: true);

    final reviewItems = <MobileInboxImportItem>[];
    for (final tx in result.newTxs) {
      final accName = accById(tx.acc)?.name ?? 'Conta';
      reviewItems.add(
        MobileInboxImportItem(
          txId: tx.id,
          accountName: accName,
          date: tx.date,
          payee: tx.payee,
          cat: tx.cat,
          memo: tx.memo,
          amt: tx.amt,
          rec: tx.rec,
        ),
      );
    }

    final sheetResult = MobileInboxImportResult(
      items: reviewItems,
      skippedCount: result.skippedCount,
      newCatsCount: result.newCats.length,
      source: 'OpenMoney Coletor Mobile',
    );

    lastImportSummary = ImportSummary(
      title: 'Lançamentos do Celular Importados',
      importedCount: result.newTxs.length,
      skippedCount: result.skippedCount,
      newCategoriesCount: result.newCats.length,
      newAccountsCount: 0,
      details: 'Origem: OpenMoney Coletor Mobile',
    );
    AuditLogManager.instance.logAsync(
      dbPath: dbPath,
      action: AuditAction.importBatch,
      entity: AuditEntity.transaction,
      summary: 'Importação Celular: ${result.newTxs.length} lançamentos adicionados, '
          '${result.skippedCount} duplicados ignorados',
    );
    notifyListeners();
    return sheetResult;
  }

  String exportCSVString({String? accountFilterId}) {
    return CSVExporter.generateCSV(
      transactions: db.txs,
      accounts: db.accounts,
      accountFilterId: accountFilterId,
    );
  }

  String exportCategoriesCSVString() {
    return CategoryCSVExporter.generateCSV(db.cats);
  }

  String exportCashFlowCSVString(CashFlowMatrix matrix) {
    return CashFlowEngine.generateCSV(matrix);
  }

  // MARK: - Navigation & Global Search

  void navigateToTransaction(Transaction tx) {
    selectedAccountId = tx.acc;
    activeModule = NavModule.account;
    _month = tx.date.length >= 7 ? tx.date.substring(0, 7) : _month;
    highlightedTxId = tx.id;
    rebuildPredictedBalances();
    notifyListeners();

    Future.delayed(const Duration(seconds: 4), () {
      if (highlightedTxId == tx.id) {
        highlightedTxId = null;
        notifyListeners();
      }
    });
  }

  List<int> allYearsInDatabase() {
    final currentY = int.tryParse(todayISO().substring(0, 4)) ?? 2026;
    final years = <int>{currentY - 1, currentY, currentY + 1};
    for (final tx in db.txs) {
      if (tx.date.length >= 4) {
        final y = int.tryParse(tx.date.substring(0, 4));
        if (y != null) years.add(y);
      }
    }
    return years.toList()..sort();
  }

  List<Transaction> searchTransactions({
    required String query,
    String? accountId,
    int signFilter = 0, // 0: all, 1: positive, -1: negative
  }) {
    final trimmed = query.trim();
    var candidates = List<Transaction>.from(db.txs);
    if (accountId != null && accountId.isNotEmpty && accountId != 'all') {
      candidates = candidates.where((t) => t.acc == accountId).toList();
    }
    if (signFilter > 0) {
      candidates = candidates.where((t) => t.amt > 0).toList();
    } else if (signFilter < 0) {
      candidates = candidates.where((t) => t.amt < 0).toList();
    }

    if (trimmed.isEmpty) {
      candidates.sort((a, b) => b.date.compareTo(a.date));
      return candidates.length > 100
          ? candidates.sublist(0, 100)
          : candidates;
    }

    final tokens = removeDiacritics(trimmed)
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();

    final accNames = {
      for (final a in db.accounts) a.id: removeDiacritics(a.name).toLowerCase()
    };

    final filtered = candidates.where((tx) {
      final payee = removeDiacritics(tx.payee).toLowerCase();
      final cat = removeDiacritics(tx.cat).toLowerCase();
      final memo = removeDiacritics(tx.memo).toLowerCase();
      final accName = accNames[tx.acc] ?? '';
      final dateStr = tx.date;
      final formattedDate = fmtDate(tx.date).toLowerCase();

      final absCents = tx.amt.abs();
      final formattedBRL = brl(tx.amt).toLowerCase();
      final formattedAbsBRL = brl(absCents).toLowerCase();
      final inputCents = formatInputCents(absCents).toLowerCase();
      final intPart = (absCents ~/ 100).toString();
      final centsStr = absCents.toString();

      for (final token in tokens) {
        final match = payee.contains(token) ||
            cat.contains(token) ||
            memo.contains(token) ||
            accName.contains(token) ||
            dateStr.contains(token) ||
            formattedDate.contains(token) ||
            formattedBRL.contains(token) ||
            formattedAbsBRL.contains(token) ||
            inputCents.contains(token) ||
            intPart == token ||
            (token.length >= 3 && centsStr.contains(token));
        if (!match) return false;
      }
      return true;
    }).toList();

    filtered.sort((a, b) => b.date.compareTo(a.date));
    return filtered;
  }

  // MARK: - Due & Reconciliation Engine (Contas a Pagar & Receber)

  List<DueBillItem> dueBillItems(
      {int? withinDays, String? accountId, Set<String>? accountIds}) {
    final horizon = withinDays ?? reminderDaysAhead;
    final today = todayISO();
    final items = <DueBillItem>[];

    for (final tx in db.txs) {
      if (tx.rec) continue;
      if (accountId != null && accountId.isNotEmpty && tx.acc != accountId) {
        continue;
      }
      if (accountIds != null &&
          accountIds.isNotEmpty &&
          !accountIds.contains(tx.acc)) {
        continue;
      }
      final acc = accById(tx.acc);
      final isCard = acc != null && acc.type == kCardType;
      String targetDate = tx.date;
      String? txIk;
      if (isCard && acc.card != null) {
        txIk = tx.ik ?? tx.inv ?? invKeyFor(acc.card!, tx.date);
        final invInfo = acc.invoices?[txIk];
        if (invInfo != null && invInfo.due.isNotEmpty) {
          targetDate = invInfo.due;
        } else {
          targetDate = invDates(acc.card!, txIk).due;
        }
      }

      final diff = daysBetween(today, targetDate);
      if (withinDays != null) {
        if (withinDays >= 0 && diff > withinDays) continue;
      } else {
        if (diff > horizon) continue;
      }
      if (diff < 0) {
        if (isCard) {
          final currentIk = acc.card != null
              ? invKeyFor(acc.card!, today)
              : (today.length >= 7 ? today.substring(0, 7) : today);
          final resolvedIk = txIk ??
              tx.ik ??
              tx.inv ??
              (acc.card != null
                  ? invKeyFor(acc.card!, tx.date)
                  : (tx.date.length >= 7 ? tx.date.substring(0, 7) : tx.date));
          if (resolvedIk != currentIk) {
            continue;
          }
        }
      }
      final accName = acc?.name ?? 'Conta';
      items.add(
        DueBillItem(
          tx: tx,
          accountName: accName,
          daysUntilDue: diff,
          dueDate: targetDate,
        ),
      );
    }

    items.sort((a, b) {
      if (a.daysUntilDue != b.daysUntilDue) {
        return a.daysUntilDue.compareTo(b.daysUntilDue);
      }
      final dc = a.effectiveDueDate.compareTo(b.effectiveDueDate);
      if (dc != 0) return dc;
      return a.tx.payee.compareTo(b.tx.payee);
    });

    return items;
  }

  ({
    int totalCount,
    int payCount,
    int payTotal,
    int receiveCount,
    int receiveTotal,
    int netTotal,
    int overdueCount,
    int dueTodayCount,
  }) dueBillsSummary(
      {int? withinDays, String? accountId, Set<String>? accountIds}) {
    final items = dueBillItems(
        withinDays: withinDays, accountId: accountId, accountIds: accountIds);
    int payCount = 0;
    int payTotal = 0;
    int recCount = 0;
    int recTotal = 0;
    int overdueCount = 0;
    int dueTodayCount = 0;

    for (final item in items) {
      if (item.isOverdue) overdueCount++;
      if (item.isDueToday) dueTodayCount++;
      if (item.isPayable) {
        payCount++;
        payTotal += item.tx.amt.abs();
      } else {
        recCount++;
        recTotal += item.tx.amt;
      }
    }

    return (
      totalCount: items.length,
      payCount: payCount,
      payTotal: payTotal,
      receiveCount: recCount,
      receiveTotal: recTotal,
      netTotal: recTotal - payTotal,
      overdueCount: overdueCount,
      dueTodayCount: dueTodayCount,
    );
  }

  /// Despesas parceladas em aberto (não conciliadas), sem limite de antecedência.
  List<DueBillItem> installmentItems({Set<String>? accountIds}) {
    final today = todayISO();
    final items = <DueBillItem>[];
    for (final tx in db.txs) {
      if (tx.rec || tx.amt >= 0) continue;
      if (tx.pt == null || tx.pt! <= 1) continue;
      if (accountIds != null &&
          accountIds.isNotEmpty &&
          !accountIds.contains(tx.acc)) {
        continue;
      }
      final acc = accById(tx.acc);
      String target = tx.date;
      if (acc != null && acc.type == kCardType && acc.card != null) {
        final ik = tx.ik ?? tx.inv ?? invKeyFor(acc.card!, tx.date);
        final info = acc.invoices?[ik];
        target = (info != null && info.due.isNotEmpty)
            ? info.due
            : invDates(acc.card!, ik).due;
      }
      items.add(DueBillItem(
        tx: tx,
        accountName: acc?.name ?? 'Conta',
        daysUntilDue: daysBetween(today, target),
        dueDate: target,
      ));
    }
    items.sort((a, b) {
      final dc = a.effectiveDueDate.compareTo(b.effectiveDueDate);
      return dc != 0 ? dc : a.tx.payee.compareTo(b.tx.payee);
    });
    return items;
  }

  /// CSV (`;`, BOM UTF-8, vírgula decimal) para itens de vencimento/parcelas.
  String dueBillsCSVString(List<DueBillItem> items) {
    String q(String v) => '"${v.replaceAll('"', '""')}"';
    const header =
        'Vencimento;Data da Compra;Conta;Negócio;Favorecido;Categoria;Parcela;Valor (R\$);Situação';
    final rows = items.map((i) {
      final t = i.tx;
      final valor = (t.amt / 100.0).toStringAsFixed(2).replaceAll('.', ',');
      final parcela = (t.pn != null && t.pt != null) ? '${t.pn}/${t.pt}' : '';
      return [
        fmtDate(i.effectiveDueDate),
        fmtDate(t.date),
        q(i.accountName),
        q(accById(t.acc)?.business ?? ''),
        q(t.payee),
        q(t.cat),
        parcela,
        valor,
        i.statusDescription,
      ].join(';');
    }).join('\r\n');
    return '\uFEFF$header\r\n$rows';
  }

  int pendingCountForAccount(String accountId) {
    return dueBillItems(
      withinDays: reminderDaysAhead,
      accountId: accountId,
    ).length;
  }

  void reconcileAllDueBills(
      {int? withinDays, Set<String>? accountIds}) {
    final items =
        dueBillItems(withinDays: withinDays, accountIds: accountIds);
    if (items.isEmpty) return;
    final ids = items.map((i) => i.tx.id).toSet();
    for (int i = 0; i < db.txs.length; i++) {
      if (ids.contains(db.txs[i].id)) {
        db.txs[i].rec = true;
        final xfer = db.txs[i].xfer;
        if (xfer != null) {
          for (int j = 0; j < db.txs.length; j++) {
            if (db.txs[j].xfer == xfer) {
              db.txs[j].rec = true;
            }
          }
        }
      }
    }
    markIndexesDirty();
    save();
  }

  @override
  void dispose() {
    _debounceSaveTimer?.cancel();
    _fileWatcherSub?.cancel();
    super.dispose();
  }
}

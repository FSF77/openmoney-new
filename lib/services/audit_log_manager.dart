import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'cloud_sync_service.dart';
import 'platform_io.dart';

enum AuditAction {
  create,
  update,
  delete,
  batchDelete,
  importBatch,
}

enum AuditEntity {
  transaction,
  account,
  category,
}

class AuditLogEntry {
  final DateTime timestamp;
  final AuditAction action;
  final AuditEntity entity;
  final String? id;
  final String summary;
  final Map<String, dynamic>? details;

  const AuditLogEntry({
    required this.timestamp,
    required this.action,
    required this.entity,
    this.id,
    required this.summary,
    this.details,
  });

  Map<String, dynamic> toJson() {
    return {
      'ts': timestamp.toIso8601String(),
      'action': action.name,
      'entity': entity.name,
      if (id != null) 'id': id,
      'summary': summary,
      if (details != null && details!.isNotEmpty) 'details': details,
    };
  }

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) {
    AuditAction parsedAction;
    try {
      parsedAction = AuditAction.values.byName(json['action'] as String? ?? 'create');
    } catch (_) {
      parsedAction = AuditAction.create;
    }

    AuditEntity parsedEntity;
    try {
      parsedEntity = AuditEntity.values.byName(json['entity'] as String? ?? 'transaction');
    } catch (_) {
      parsedEntity = AuditEntity.transaction;
    }

    DateTime dt;
    try {
      dt = DateTime.parse(json['ts'] as String);
    } catch (_) {
      dt = DateTime.now();
    }

    return AuditLogEntry(
      timestamp: dt,
      action: parsedAction,
      entity: parsedEntity,
      id: json['id'] as String?,
      summary: json['summary'] as String? ?? '',
      details: json['details'] is Map<String, dynamic> ? json['details'] as Map<String, dynamic> : null,
    );
  }

  String get actionLabel {
    switch (action) {
      case AuditAction.create:
        return 'Inclusão';
      case AuditAction.update:
        return 'Alteração';
      case AuditAction.delete:
        return 'Exclusão';
      case AuditAction.batchDelete:
        return 'Exclusão em Lote';
      case AuditAction.importBatch:
        return 'Importação';
    }
  }

  String get entityLabel {
    switch (entity) {
      case AuditEntity.transaction:
        return 'Lançamento';
      case AuditEntity.account:
        return 'Conta';
      case AuditEntity.category:
        return 'Categoria';
    }
  }

  String get formattedDate {
    final d = timestamp;
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    final year = d.year.toString();
    final hour = d.hour.toString().padLeft(2, '0');
    final minute = d.minute.toString().padLeft(2, '0');
    final second = d.second.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute:$second';
  }
}

class AuditLogManager {
  static final AuditLogManager instance = AuditLogManager._();
  AuditLogManager._();

  String? defaultAppSupportDirPath;
  final List<AuditLogEntry> _pendingCloudLogs = [];
  Timer? _cloudFlushTimer;

  /// Resolve o arquivo de log a partir do caminho da base (local ou nuvem no desktop)
  String logFilePathForDatabase(String dbPath, {String? appSupportDirPath}) {
    if (dbPath.isEmpty) return '';
    if (dbPath.startsWith('cloud://')) {
      final baseDir = appSupportDirPath ?? defaultAppSupportDirPath;
      if (baseDir == null || baseDir.isEmpty) return '';
      final email = dbPath.replaceFirst('cloud://', '').trim();
      final clean = email.replaceAll(RegExp(r'[^a-zA-Z0-9_\.-]'), '_');
      final sep = Platform.pathSeparator;
      final dir = Directory('$baseDir${sep}AuditLogs');
      if (!dir.existsSync()) {
        try {
          dir.createSync(recursive: true);
        } catch (_) {}
      }
      return '${dir.path}${sep}openmoney-cloud-$clean.log';
    }
    final dotIdx = dbPath.lastIndexOf('.');
    if (dotIdx == -1) {
      return '$dbPath.log';
    }
    return '${dbPath.substring(0, dotIdx)}.log';
  }

  void _enqueueCloudLog(AuditLogEntry entry) {
    _pendingCloudLogs.add(entry);
    _cloudFlushTimer?.cancel();
    _cloudFlushTimer = Timer(const Duration(milliseconds: 400), () {
      flushCloudLogs();
    });
  }

  /// Força o envio imediato de logs pendentes para o banco online D1
  Future<void> flushCloudLogs() async {
    _cloudFlushTimer?.cancel();
    _cloudFlushTimer = null;
    if (_pendingCloudLogs.isEmpty) return;
    final toSend = List<AuditLogEntry>.from(_pendingCloudLogs);
    _pendingCloudLogs.clear();
    try {
      await CloudSyncService.instance.sendAuditLogs(toSend);
    } catch (e) {
      debugPrint('[AuditLogManager] Erro ao enviar logs para a nuvem: $e');
    }
  }

  /// Grava uma entrada de auditoria de forma assíncrona (localmente e no banco online se Cloud)
  void logAsync({
    required String dbPath,
    String? appSupportDirPath,
    required AuditAction action,
    required AuditEntity entity,
    String? id,
    required String summary,
    Map<String, dynamic>? details,
  }) {
    final entry = AuditLogEntry(
      timestamp: DateTime.now(),
      action: action,
      entity: entity,
      id: id,
      summary: summary,
      details: details,
    );

    // 1. Se estiver em modo online ou autenticado no CloudSync, enfileira para salvar no banco D1
    final isCloud = dbPath.startsWith('cloud://') ||
        CloudSyncService.instance.isAuthenticated;
    if (isCloud) {
      _enqueueCloudLog(entry);
    }

    // 2. Se não estiver na Web, grava também no arquivo local .log (incluindo base cloud no desktop)
    if (!kIsWeb) {
      Future.microtask(() async {
        try {
          final logPath = logFilePathForDatabase(
            dbPath,
            appSupportDirPath: appSupportDirPath,
          );
          if (logPath.isEmpty) return;
          final file = File(logPath);
          if (!file.existsSync()) {
            file.createSync(recursive: true);
          }
          final line = '${jsonEncode(entry.toJson())}\n';
          await file.writeAsString(line,
              mode: FileMode.writeOnlyAppend, flush: false);
        } catch (e) {
          debugPrint('[AuditLogManager] Erro ao gravar log: $e');
        }
      });
    }
  }

  /// Lê os logs mais recentes (até `limit` registros, decrescente)
  /// Se a base for online, busca do banco online Cloudflare D1
  Future<List<AuditLogEntry>> readRecentLogs({
    required String dbPath,
    String? appSupportDirPath,
    int limit = 500,
  }) async {
    final isCloud = dbPath.startsWith('cloud://') ||
        (kIsWeb && CloudSyncService.instance.isAuthenticated) ||
        CloudSyncService.instance.isAuthenticated;

    // 1. Em modo Cloud, busca os logs direto do banco online D1
    if (isCloud && CloudSyncService.instance.isAuthenticated) {
      await flushCloudLogs();
      final remoteLogs =
          await CloudSyncService.instance.fetchAuditLogs(limit: limit);
      if (remoteLogs.isNotEmpty) {
        return remoteLogs;
      }
    }

    // 2. Fallback offline ou base estritamente local
    if (kIsWeb) return [];
    try {
      final logPath = logFilePathForDatabase(
        dbPath,
        appSupportDirPath: appSupportDirPath,
      );
      if (logPath.isEmpty) return [];
      final file = File(logPath);
      if (!await file.exists()) return [];

      final lines = await file.readAsLines();
      final entries = <AuditLogEntry>[];
      for (int i = lines.length - 1; i >= 0 && entries.length < limit; i--) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        try {
          final decoded = jsonDecode(line);
          if (decoded is Map<String, dynamic>) {
            entries.add(AuditLogEntry.fromJson(decoded));
          }
        } catch (_) {}
      }
      return entries;
    } catch (e) {
      debugPrint('[AuditLogManager] Erro ao ler logs: $e');
      return [];
    }
  }

  /// Expura logs com mais de `retentionDays` dias (padrão 30 dias)
  Future<void> pruneOldLogs({
    required String dbPath,
    String? appSupportDirPath,
    int retentionDays = 30,
  }) async {
    if (kIsWeb || dbPath.isEmpty) return;
    try {
      final logPath = logFilePathForDatabase(
        dbPath,
        appSupportDirPath: appSupportDirPath,
      );
      if (logPath.isEmpty) return;
      final file = File(logPath);
      if (!await file.exists()) return;

      final cutoff = DateTime.now().subtract(Duration(days: retentionDays));
      final lines = await file.readAsLines();
      if (lines.isEmpty) return;

      // Otimização: checa a primeira linha. Se for posterior ao cutoff, todas são recentes
      try {
        final firstMap = jsonDecode(lines.first.trim());
        if (firstMap is Map<String, dynamic> && firstMap['ts'] != null) {
          final firstDate = DateTime.tryParse(firstMap['ts'] as String);
          if (firstDate != null && firstDate.isAfter(cutoff)) {
            // Nenhuma linha precisa ser removida
            return;
          }
        }
      } catch (_) {}

      // Filtra as linhas dentro da janela de retenção
      final validLines = <String>[];
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is Map<String, dynamic> && decoded['ts'] != null) {
            final dt = DateTime.tryParse(decoded['ts'] as String);
            if (dt != null && dt.isAfter(cutoff)) {
              validLines.add(trimmed);
            }
          }
        } catch (_) {
          // Em caso de erro na linha antiga, preserva se for recente ou descarta
        }
      }

      if (validLines.length != lines.length) {
        final tempFile = File('$logPath.tmp');
        await tempFile.writeAsString(
          validLines.isEmpty ? '' : '${validLines.join('\n')}\n',
          flush: true,
        );
        if (await tempFile.exists()) {
          await tempFile.rename(logPath);
        }
      }
    } catch (e) {
      debugPrint('[AuditLogManager] Erro ao podar logs: $e');
    }
  }
}

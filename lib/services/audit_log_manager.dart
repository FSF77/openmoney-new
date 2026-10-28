import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

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

  /// Resolve o arquivo de log a partir do caminho da base
  String logFilePathForDatabase(String dbPath) {
    if (dbPath.isEmpty) return '';
    final dotIdx = dbPath.lastIndexOf('.');
    if (dotIdx == -1) {
      return '$dbPath.log';
    }
    return '${dbPath.substring(0, dotIdx)}.log';
  }

  /// Grava uma entrada de auditoria de forma assíncrona append-only sem travar a UI
  void logAsync({
    required String dbPath,
    required AuditAction action,
    required AuditEntity entity,
    String? id,
    required String summary,
    Map<String, dynamic>? details,
  }) {
    if (kIsWeb || dbPath.isEmpty) return;

    final entry = AuditLogEntry(
      timestamp: DateTime.now(),
      action: action,
      entity: entity,
      id: id,
      summary: summary,
      details: details,
    );

    // Executa em microtask/async I/O
    Future.microtask(() async {
      try {
        final logPath = logFilePathForDatabase(dbPath);
        if (logPath.isEmpty) return;
        final file = File(logPath);
        final line = '${jsonEncode(entry.toJson())}\n';
        await file.writeAsString(line, mode: FileMode.writeOnlyAppend, flush: false);
      } catch (e) {
        debugPrint('[AuditLogManager] Erro ao gravar log: $e');
      }
    });
  }

  /// Lê os logs mais recentes (até `limit` registros, decrescente)
  Future<List<AuditLogEntry>> readRecentLogs({
    required String dbPath,
    int limit = 500,
  }) async {
    if (kIsWeb || dbPath.isEmpty) return [];
    try {
      final logPath = logFilePathForDatabase(dbPath);
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
    int retentionDays = 30,
  }) async {
    if (kIsWeb || dbPath.isEmpty) return;
    try {
      final logPath = logFilePathForDatabase(dbPath);
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

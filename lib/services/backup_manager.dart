import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import '../models/openmoney_models.dart';

class BackupFileInfo {
  final String path;
  final String filename;
  final DateTime date;
  final int sizeBytes;

  const BackupFileInfo({
    required this.path,
    required this.filename,
    required this.date,
    required this.sizeBytes,
  });

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get formattedDate {
    final d = date;
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    final year = d.year.toString();
    final hour = d.hour.toString().padLeft(2, '0');
    final minute = d.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }
}

class BackupManager {
  BackupManager._();
  static final BackupManager instance = BackupManager._();

  Directory getBackupsDirectory(String appSupportDirPath) {
    final sep = Platform.pathSeparator;
    final dir = Directory('$appSupportDirPath${sep}Backups');
    if (!dir.existsSync()) {
      try {
        dir.createSync(recursive: true);
      } catch (_) {}
    }
    return dir;
  }

  /// Garante que exista ao menos 1 backup em .zip para o dia atual e expurga os que têm mais de 7 dias
  Future<void> ensureDailyBackup({
    required String appSupportDirPath,
    required String databasePath,
    bool force = false,
  }) async {
    if (kIsWeb || databasePath.isEmpty) return;
    final dbFile = File(databasePath);
    if (!dbFile.existsSync()) return;

    final backupsDir = getBackupsDirectory(appSupportDirPath);
    final today = todayISO(); // YYYY-MM-DD
    final baseName = dbFile.uri.pathSegments.last.replaceAll(RegExp(r'\.json$', caseSensitive: false), '');
    final sep = Platform.pathSeparator;
    final zipFilename = '$baseName-backup-$today.zip';
    final destZipFile = File('${backupsDir.path}$sep$zipFilename');

    if (!force && destZipFile.existsSync()) {
      return;
    }

    try {
      final success = await createZipArchive(
        sourcePath: databasePath,
        destinationZipPath: destZipFile.path,
      );
      if (success) {
        pruneBackups(
          appSupportDirPath: appSupportDirPath,
          retentionDays: 7,
          minBackupsToKeep: 7,
        );
      }
    } catch (e) {
      debugPrint('[BackupManager] Erro no ensureDailyBackup: $e');
    }
  }

  /// Cria um backup pontual em .zip (por exemplo, manual ou pré-exclusão)
  Future<String?> createTimestampedBackup({
    required String appSupportDirPath,
    required String databasePath,
    String prefix = 'backup',
  }) async {
    if (kIsWeb || databasePath.isEmpty) return null;
    final dbFile = File(databasePath);
    if (!dbFile.existsSync()) return null;

    final backupsDir = getBackupsDirectory(appSupportDirPath);
    final now = DateTime.now();
    final ts = '${now.year.toString().padLeft(4, "0")}-'
        '${now.month.toString().padLeft(2, "0")}-'
        '${now.day.toString().padLeft(2, "0")}_'
        '${now.hour.toString().padLeft(2, "0")}'
        '${now.minute.toString().padLeft(2, "0")}'
        '${now.second.toString().padLeft(2, "0")}';

    final baseName = dbFile.uri.pathSegments.last.replaceAll(RegExp(r'\.json$', caseSensitive: false), '');
    final sep = Platform.pathSeparator;
    final zipFilename = '$baseName-$prefix-$ts.zip';
    final destZipFile = File('${backupsDir.path}$sep$zipFilename');

    final success = await createZipArchive(
      sourcePath: databasePath,
      destinationZipPath: destZipFile.path,
    );
    if (success) {
      pruneBackups(
        appSupportDirPath: appSupportDirPath,
        retentionDays: 7,
        minBackupsToKeep: 7,
      );
      return destZipFile.path;
    }
    return null;
  }

  /// Compacta o arquivo JSON de origem em um arquivo .zip
  Future<bool> createZipArchive({
    required String sourcePath,
    required String destinationZipPath,
  }) async {
    if (kIsWeb) return false;
    final sourceFile = File(sourcePath);
    if (!sourceFile.existsSync()) return false;

    // Tenta usar /usr/bin/zip nativo no macOS para velocidade e compatibilidade 1:1
    if (Platform.isMacOS) {
      try {
        final parentDir = Directory.systemTemp.createTempSync('om_zip_');
        final stagedFile = File('${parentDir.path}/${sourceFile.uri.pathSegments.last}');
        sourceFile.copySync(stagedFile.path);

        final destFile = File(destinationZipPath);
        if (destFile.existsSync()) {
          try {
            destFile.deleteSync();
          } catch (_) {}
        }

        final res = await Process.run(
          '/usr/bin/zip',
          ['-q', '-9', destinationZipPath, sourceFile.uri.pathSegments.last],
          workingDirectory: parentDir.path,
        );

        try {
          parentDir.deleteSync(recursive: true);
        } catch (_) {}

        if (res.exitCode == 0 && File(destinationZipPath).existsSync()) {
          return true;
        }
      } catch (_) {}
    }

    // Fallback universal multiplataforma via pacote archive
    try {
      final bytes = sourceFile.readAsBytesSync();
      final archive = Archive();
      final fileName = sourceFile.uri.pathSegments.last;
      archive.addFile(ArchiveFile(fileName, bytes.length, bytes));

      final zipData = ZipEncoder().encode(archive);
      final destFile = File(destinationZipPath);
      destFile.parent.createSync(recursive: true);
      destFile.writeAsBytesSync(zipData, flush: true);
      return true;
    } catch (e) {
      debugPrint('[BackupManager] Erro ao criar zip archive: $e');
      return false;
    }
  }

  /// Extrai o arquivo .zip e obtém os dados do JSON contido nele
  Future<Database?> extractDatabase({required String zipPath}) async {
    if (kIsWeb) return null;
    final zipFile = File(zipPath);
    if (!zipFile.existsSync()) return null;

    // Se no macOS, tenta usar /usr/bin/unzip nativo
    if (Platform.isMacOS) {
      try {
        final tempDir = Directory.systemTemp.createTempSync('om_unzip_');
        final res = await Process.run(
          '/usr/bin/unzip',
          ['-q', '-o', zipPath, '-d', tempDir.path],
        );
        if (res.exitCode == 0) {
          final files = tempDir.listSync(recursive: true);
          File? jsonFile;
          for (final f in files) {
            if (f is File && f.path.toLowerCase().endsWith('.json')) {
              jsonFile = f;
              break;
            }
          }
          if (jsonFile != null) {
            final raw = jsonFile.readAsStringSync();
            try {
              tempDir.deleteSync(recursive: true);
            } catch (_) {}
            final decoded = jsonDecode(raw) as Map<String, dynamic>;
            return Database.fromJson(decoded);
          }
        }
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      } catch (_) {}
    }

    // Fallback multiplataforma via pacote archive
    try {
      final bytes = zipFile.readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final file in archive) {
        if (file.isFile && file.name.toLowerCase().endsWith('.json')) {
          final content = utf8.decode(file.content as List<int>);
          final decoded = jsonDecode(content) as Map<String, dynamic>;
          return Database.fromJson(decoded);
        }
      }
    } catch (e) {
      debugPrint('[BackupManager] Erro ao extrair banco do zip: $e');
    }
    return null;
  }

  /// Remove backups mais antigos que `retentionDays`, garantindo manter no mínimo `minBackupsToKeep`
  void pruneBackups({
    required String appSupportDirPath,
    int retentionDays = 7,
    int minBackupsToKeep = 7,
  }) {
    if (kIsWeb) return;
    try {
      final dir = getBackupsDirectory(appSupportDirPath);
      if (!dir.existsSync()) return;

      final entities = dir.listSync();
      final zipFiles = <({File file, DateTime date})>[];

      for (final e in entities) {
        if (e is File && e.path.toLowerCase().endsWith('.zip')) {
          try {
            final stat = e.statSync();
            zipFiles.add((file: e, date: stat.modified));
          } catch (_) {}
        }
      }

      // Mais recentes primeiro
      zipFiles.sort((a, b) => b.date.compareTo(a.date));

      if (zipFiles.length <= minBackupsToKeep) return;

      final cutoffDate = DateTime.now().subtract(Duration(days: retentionDays));

      for (int i = minBackupsToKeep; i < zipFiles.length; i++) {
        final item = zipFiles[i];
        if (item.date.isBefore(cutoffDate)) {
          try {
            item.file.deleteSync();
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[BackupManager] Erro no pruneBackups: $e');
    }
  }

  /// Lista todos os backups disponíveis ordenados do mais recente para o mais antigo
  List<BackupFileInfo> availableBackups({required String appSupportDirPath}) {
    if (kIsWeb) return [];
    try {
      final dir = getBackupsDirectory(appSupportDirPath);
      if (!dir.existsSync()) return [];

      final list = <BackupFileInfo>[];
      for (final entity in dir.listSync()) {
        if (entity is File && entity.path.toLowerCase().endsWith('.zip')) {
          try {
            final stat = entity.statSync();
            list.add(BackupFileInfo(
              path: entity.path,
              filename: entity.uri.pathSegments.last,
              date: stat.modified,
              sizeBytes: stat.size,
            ));
          } catch (_) {}
        }
      }

      list.sort((a, b) => b.date.compareTo(a.date));
      return list;
    } catch (e) {
      debugPrint('[BackupManager] Erro ao listar backups: $e');
      return [];
    }
  }

  /// Revela a pasta de backups no Finder (macOS) ou Explorer (Windows)
  void revealInFinder(String appSupportDirPath) {
    if (kIsWeb) return;
    final dir = getBackupsDirectory(appSupportDirPath);
    if (!dir.existsSync()) {
      try {
        dir.createSync(recursive: true);
      } catch (_) {}
    }
    if (Platform.isMacOS) {
      Process.run('open', [dir.path]);
    } else if (Platform.isWindows) {
      Process.run('explorer.exe', [dir.path]);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [dir.path]);
    }
  }
}

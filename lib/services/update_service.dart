import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../ui/theme/liquid_glass.dart';

class OpenMoneyVersion {
  static const String fallbackVersion = '2.1.8';
  static const int fallbackBuild = 30;
  static const String releasesRepoUrl = 'https://github.com/FSF77/openmoney-new';
  static const String feedUrl =
      'https://raw.githubusercontent.com/FSF77/openmoney-new/main/version.json';

  static String _version = fallbackVersion;
  static int _build = fallbackBuild;
  static bool _initialized = false;

  static String get version => _version;
  static int get build => _build;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      // No Windows, limpa eventuais arquivos .old_update deixados pela atualização in-place anterior
      if (!kIsWeb && Platform.isWindows) {
        _cleanupOldWindowsUpdateFiles();
      }
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) {
        final parsedBuild = int.tryParse(info.buildNumber);
        // Usa o PackageInfo apenas se não for menor que o fallback compilado no código Dart
        if (UpdateService.isVersionGreaterThan(
              info.version,
              parsedBuild,
              fallbackVersion,
              fallbackBuild,
            ) ||
            info.version == fallbackVersion) {
          _version = info.version;
          if (parsedBuild != null) {
            _build = parsedBuild;
          }
        }
      }
    } catch (_) {}
    _initialized = true;
  }

  static void _cleanupOldWindowsUpdateFiles() {
    try {
      final appDir = File(Platform.resolvedExecutable).parent;
      for (final entity in appDir.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.old_update')) {
          try {
            entity.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}

class ReleaseVersionInfo {
  final String version;
  final int? build;
  final String? releaseDate;
  final String? title;
  final String? notes;
  final String downloadUrl;
  final String? githubReleaseUrl;
  final String? sha256;

  const ReleaseVersionInfo({
    required this.version,
    this.build,
    this.releaseDate,
    this.title,
    this.notes,
    required this.downloadUrl,
    this.githubReleaseUrl,
    this.sha256,
  });

  factory ReleaseVersionInfo.fromJson(Map<String, dynamic> json) {
    // Detect platform-specific payload (macos or windows)
    Map<String, dynamic> platformData = json;
    if (Platform.isMacOS && json['macos'] is Map<String, dynamic>) {
      platformData = json['macos'] as Map<String, dynamic>;
    } else if (Platform.isWindows && json['windows'] is Map<String, dynamic>) {
      platformData = json['windows'] as Map<String, dynamic>;
    }

    final rawVersion = (platformData['version'] ?? json['version'] ?? '1.0.0').toString();
    final rawBuild = platformData['build'] ?? json['build'];
    int? parsedBuild;
    if (rawBuild is int) {
      parsedBuild = rawBuild;
    } else if (rawBuild is String) {
      parsedBuild = int.tryParse(rawBuild);
    }

    final downloadUrl = (platformData['downloadUrl'] ?? json['downloadUrl'] ?? '').toString();

    return ReleaseVersionInfo(
      version: rawVersion,
      build: parsedBuild,
      releaseDate: (platformData['releaseDate'] ?? json['releaseDate'])?.toString(),
      title: (platformData['title'] ?? json['title'])?.toString(),
      notes: (platformData['notes'] ?? json['notes'])?.toString(),
      downloadUrl: downloadUrl,
      githubReleaseUrl: (platformData['githubReleaseUrl'] ?? json['githubReleaseUrl'])?.toString(),
      sha256: (platformData['sha256'] ?? json['sha256'])?.toString(),
    );
  }
}

class UpdateService {
  static bool _isChecking = false;

  static bool isVersionGreaterThan(
    String remote,
    int? remoteBuild,
    String local,
    int? localBuild,
  ) {
    final cleanRemote = remote.replaceAll(RegExp(r'^[vV\s]+'), '').trim();
    final cleanLocal = local.replaceAll(RegExp(r'^[vV\s]+'), '').trim();

    final rParts = cleanRemote.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final lParts = cleanLocal.split('.').map((s) => int.tryParse(s) ?? 0).toList();

    final count = rParts.length > lParts.length ? rParts.length : lParts.length;
    for (int i = 0; i < count; i++) {
      final r = i < rParts.length ? rParts[i] : 0;
      final l = i < lParts.length ? lParts[i] : 0;
      if (r > l) return true;
      if (r < l) return false;
    }

    if (remoteBuild != null && localBuild != null) {
      return remoteBuild > localBuild;
    }

    return false;
  }

  static Future<ReleaseVersionInfo?> checkRemoteUpdate() async {
    if (kIsWeb) return null;
    if (_isChecking) return null;
    _isChecking = true;

    try {
      await OpenMoneyVersion.init();
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 7);

      // Attempt to fetch latest commit sha on main branch to bypass GitHub raw CDN caching
      String targetUrl = '${OpenMoneyVersion.feedUrl}?t=${DateTime.now().millisecondsSinceEpoch}';
      try {
        final commitUri = Uri.parse(
          'https://api.github.com/repos/FSF77/openmoney-new/commits/main',
        );
        final commitReq = await client.getUrl(commitUri);
        commitReq.headers.set('User-Agent', 'OpenMoney-App');
        final commitRes = await commitReq.close();
        if (commitRes.statusCode == 200) {
          final commitBody = await commitRes.transform(utf8.decoder).join();
          final commitJson = jsonDecode(commitBody) as Map<String, dynamic>;
          final sha = commitJson['sha'] as String?;
          if (sha != null && sha.isNotEmpty) {
            targetUrl =
                'https://raw.githubusercontent.com/FSF77/openmoney-new/$sha/version.json';
          }
        }
      } catch (_) {
        // Fallback to timestamped raw URL
      }

      final feedReq = await client.getUrl(Uri.parse(targetUrl));
      feedReq.headers.set('User-Agent', 'OpenMoney-App');
      final feedRes = await feedReq.close();

      if (feedRes.statusCode != 200) {
        return null;
      }

      final body = await feedRes.transform(utf8.decoder).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final info = ReleaseVersionInfo.fromJson(decoded);

      final hasUpdate = isVersionGreaterThan(
        info.version,
        info.build,
        OpenMoneyVersion.version,
        OpenMoneyVersion.build,
      );

      if (hasUpdate && info.downloadUrl.isNotEmpty) {
        return info;
      }
      return null;
    } catch (e) {
      debugPrint('[UpdateService] Erro ao consultar atualizações: $e');
      return null;
    } finally {
      _isChecking = false;
    }
  }

  static Future<void> showUpdateDialog(
    BuildContext context, {
    bool manual = false,
  }) async {
    if (kIsWeb) return;

    if (manual) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Verificando atualizações no servidor...'),
          duration: Duration(seconds: 2),
        ),
      );
    }

    final updateInfo = await checkRemoteUpdate();

    if (!context.mounted) return;

    if (updateInfo == null) {
      if (manual) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.verified, color: Colors.green),
                SizedBox(width: 8),
                Text('OpenMoney Atualizado'),
              ],
            ),
            content: Text(
              'Você já está utilizando a versão mais recente do OpenMoney (v${OpenMoneyVersion.version}).',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return;
    }

    // Show dialog with update info and automatic download/install option
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _UpdateDialog(info: updateInfo),
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  final ReleaseVersionInfo info;
  const _UpdateDialog({required this.info});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  String _statusMessage = '';
  String? _errorMessage;

  Future<void> _startUpdate() async {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _progress = 0.0;
      _statusMessage = 'Conectando ao servidor...';
    });

    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(widget.info.downloadUrl));
      request.headers.set('User-Agent', 'OpenMoney-App');
      final response = await request.close();

      if (response.statusCode != 200 && response.statusCode != 302 && response.statusCode != 301) {
        throw Exception('Servidor retornou código HTTP ${response.statusCode}');
      }

      // Handle redirect if needed
      HttpClientResponse finalResponse = response;
      if (response.isRedirect) {
        final redirectUrl = response.headers.value(HttpHeaders.locationHeader);
        if (redirectUrl != null) {
          final redReq = await client.getUrl(Uri.parse(redirectUrl));
          finalResponse = await redReq.close();
        }
      }

      final contentLength = finalResponse.contentLength;
      final tempDir = Directory.systemTemp.createTempSync('openmoney_update_');
      final zipFile = File('${tempDir.path}${Platform.pathSeparator}update.zip');
      final sink = zipFile.openWrite();

      int downloaded = 0;
      await for (final chunk in finalResponse) {
        downloaded += chunk.length;
        sink.add(chunk);
        if (contentLength > 0) {
          final p = (downloaded / contentLength).clamp(0.0, 1.0);
          final currentMB = downloaded / (1024 * 1024);
          final totalMB = contentLength / (1024 * 1024);
          if (mounted) {
            setState(() {
              _progress = p;
              _statusMessage =
                  'Baixando: ${currentMB.toStringAsFixed(1)} MB de ${totalMB.toStringAsFixed(1)} MB (${(p * 100).toInt()}%)';
            });
          }
        } else {
          final currentMB = downloaded / (1024 * 1024);
          if (mounted) {
            setState(() {
              _statusMessage = 'Baixando: ${currentMB.toStringAsFixed(1)} MB...';
            });
          }
        }
      }
      await sink.flush();
      await sink.close();

      if (mounted) {
        setState(() {
          _statusMessage = 'Extraindo e aplicando atualização...';
        });
      }

      if (Platform.isMacOS) {
        await _applyUpdateMac(tempDir, zipFile);
      } else if (Platform.isWindows) {
        await _applyUpdateWindows(tempDir, zipFile);
      } else {
        throw Exception('Atualização automática não suportada nesta plataforma.');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = 'Falha ao atualizar: $e';
        });
      }
    }
  }

  Future<void> _applyUpdateMac(Directory tempDir, File zipFile) async {
    // Unzip via ditto to preserve symlinks and attributes
    final dittoRes = await Process.run('/usr/bin/ditto', [
      '-x',
      '-k',
      zipFile.path,
      tempDir.path,
    ]);
    if (dittoRes.exitCode != 0) {
      throw Exception('Falha ao descompactar atualização: ${dittoRes.stderr}');
    }

    // Locate OpenMoney.app inside tempDir
    final entries = tempDir.listSync(recursive: false);
    FileSystemEntity? appEntity;
    for (final e in entries) {
      if (e.path.endsWith('.app')) {
        appEntity = e;
        break;
      }
    }
    if (appEntity == null) {
      throw Exception('OpenMoney.app não encontrado no pacote baixado.');
    }

    // Clear quarantine
    await Process.run('/usr/bin/xattr', ['-cr', appEntity.path]);

    final currentExe = Platform.resolvedExecutable;
    // Walk up to find the enclosing .app bundle
    var currentAppPath = '';
    var parent = File(currentExe).parent;
    while (parent.path != parent.parent.path) {
      if (parent.path.endsWith('.app')) {
        currentAppPath = parent.path;
        break;
      }
      parent = parent.parent;
    }

    if (currentAppPath.isEmpty) {
      currentAppPath = '/Applications/OpenMoney.app';
    }

    final currentPid = pid;
    final scriptPath = '/tmp/openmoney_updater_$currentPid.sh';
    final scriptContent = '''#!/bin/bash
exec > /tmp/openmoney_updater.log 2>&1
PID="$currentPid"
NEW_APP="${appEntity.path}"
TARGET_APP="$currentAppPath"

for i in {1..75}; do
    if ! kill -0 "\$PID" 2>/dev/null; then
        break
    fi
    sleep 0.2
done

rm -rf "\$TARGET_APP"
cp -R "\$NEW_APP" "\$TARGET_APP"
xattr -cr "\$TARGET_APP" 2>/dev/null || true
rm -rf "${tempDir.path}"
rm -f "$scriptPath"

open "\$TARGET_APP"
exit 0
''';

    File(scriptPath).writeAsStringSync(scriptContent, flush: true);
    await Process.run('/bin/chmod', ['+x', scriptPath]);

    // Executa o script diretamente como processo desanexado do SO
    await Process.start(
      '/bin/bash',
      [scriptPath],
      mode: ProcessStartMode.detached,
    );

    // Pequena pausa para garantir o fork no SO antes de terminar
    await Future.delayed(const Duration(milliseconds: 250));
    exit(0);
  }

  Future<void> _applyUpdateWindows(Directory tempDir, File zipFile) async {
    final extractDir = '${tempDir.path}\\extracted';
    Directory(extractDir).createSync(recursive: true);

    // 1. Extração primária nativa em Dart via pacote 'archive'
    // Vantagem para o Windows Defender: arquivos gravados direto pelo processo Dart
    // não recebem a tag NTFS Zone.Identifier (Mark of the Web) de downloads externos,
    // e apagamos o arquivo .zip logo após extrair para não acionar escaneamento de zip em Temp.
    bool extractedOk = false;
    try {
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final file in archive) {
        final normalizedName = file.name.replaceAll('/', '\\');
        final outPath = '$extractDir\\$normalizedName';
        if (file.isFile) {
          final outFile = File(outPath);
          outFile.parent.createSync(recursive: true);
          outFile.writeAsBytesSync(file.content as List<int>, flush: true);
        } else {
          Directory(outPath).createSync(recursive: true);
        }
      }
      extractedOk = File('$extractDir\\openmoney.exe').existsSync() ||
          Directory('$extractDir\\data').existsSync();
    } catch (e) {
      debugPrint('[UpdateService] Fallback para extração externa: $e');
    }

    // 2. Fallback caso necessário
    if (!extractedOk) {
      var res = await Process.run('tar', ['-xf', zipFile.path, '-C', extractDir]);
      if (res.exitCode != 0) {
        await Process.run('powershell', [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          'Expand-Archive -LiteralPath "${zipFile.path}" -DestinationPath "$extractDir" -Force',
        ]);
      }
    }

    // Remove o .zip baixado imediatamente para evitar falsos positivos do Defender sobre zips em %TEMP%
    try {
      if (zipFile.existsSync()) {
        zipFile.deleteSync();
      }
    } catch (_) {}

    // Localiza a pasta raiz dos arquivos extraídos
    String sourceDir = extractDir;
    if (!File('$sourceDir\\openmoney.exe').existsSync()) {
      final subDirs = Directory(extractDir)
          .listSync()
          .whereType<Directory>()
          .toList();
      for (final sub in subDirs) {
        if (File('${sub.path}\\openmoney.exe').existsSync()) {
          sourceDir = sub.path;
          break;
        }
      }
    }

    if (!File('$sourceDir\\openmoney.exe').existsSync() &&
        !Directory('$sourceDir\\data').existsSync()) {
      throw Exception('Pacote de atualização inválido ou corrompido após extração.');
    }

    final currentExe = Platform.resolvedExecutable;
    final targetDir = File(currentExe).parent.path;

    // 3. Substituição in-place diretamente em Dart ANTES de fechar o aplicativo!
    // No Windows, um executável ou DLL em execução NÃO pode ser sobrescrito/deletado,
    // MAS PODE SER RENOMEADO livremente pelo próprio processo!
    // Fazemos isso diretamente no Dart sem precisar de scripts .vbs/.bat/.ps1 suspeitos para o Defender.
    final oldFilesToCleanup = <String>[];

    void replaceDirectoryContents(Directory src, String dstPath) {
      Directory(dstPath).createSync(recursive: true);
      for (final entity in src.listSync(recursive: false)) {
        final name = entity.path.split(Platform.pathSeparator).last;
        final targetEntityPath = '$dstPath${Platform.pathSeparator}$name';

        if (entity is Directory) {
          replaceDirectoryContents(entity, targetEntityPath);
        } else if (entity is File) {
          final targetFile = File(targetEntityPath);
          if (targetFile.existsSync()) {
            try {
              // Tenta sobrescrever diretamente primeiro (funciona para arquivos não travados)
              entity.copySync(targetEntityPath);
              continue;
            } catch (_) {
              // Se o arquivo estiver em uso (ex: openmoney.exe, flutter_windows.dll, app.so),
              // renomeia o arquivo em uso para .old_update e copia o novo no lugar!
              final oldPath = '$targetEntityPath.old_update';
              try {
                if (File(oldPath).existsSync()) {
                  File(oldPath).deleteSync();
                }
              } catch (_) {}
              try {
                targetFile.renameSync(oldPath);
                oldFilesToCleanup.add(oldPath);
              } catch (e) {
                debugPrint('[UpdateService] Falha ao renomear arquivo em uso $targetEntityPath: $e');
              }
            }
          }
          // Copia o arquivo novo para o caminho original
          entity.copySync(targetEntityPath);
        }
      }
    }

    // Executa a atualização in-place completa com verificação real em Dart
    replaceDirectoryContents(Directory(sourceDir), targetDir);

    // Limpa os arquivos temporários extraídos
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}

    // 4. Inicia a nova versão do executável (que já está atualizada no disco!)
    await Process.start(
      currentExe,
      const [],
      workingDirectory: targetDir,
      mode: ProcessStartMode.detached,
    );

    await Future.delayed(const Duration(milliseconds: 300));
    exit(0);
  }

  void _openManualDownload() {
    final url = widget.info.downloadUrl.isNotEmpty
        ? widget.info.downloadUrl
        : (widget.info.githubReleaseUrl ?? OpenMoneyVersion.releasesRepoUrl);

    if (Platform.isMacOS) {
      Process.run('open', [url]);
    } else if (Platform.isWindows) {
      Process.run('cmd', ['/c', 'start', '', url]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);

    return Dialog(
      backgroundColor: colors.bgSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.borderGlass),
      ),
      child: SizedBox(
        width: 520,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [colors.accent, colors.accentIndigo],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.system_update_alt,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.info.title ?? 'Nova Versão Disponível!',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          'Versão ${widget.info.version} (Atual: v${OpenMoneyVersion.version})${widget.info.releaseDate != null ? " • ${widget.info.releaseDate}" : ""}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              if (widget.info.notes != null && widget.info.notes!.isNotEmpty) ...[
                const Text(
                  'Novidades e Alterações:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 180),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.surfaceGlass,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.borderGlass),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      widget.info.notes!,
                      style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (_isDownloading) ...[
                Text(
                  _statusMessage,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  minHeight: 6,
                ),
                const SizedBox(height: 14),
              ],
              if (_errorMessage != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.expense.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.expense),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(fontSize: 12, color: colors.expense),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.open_in_browser, size: 16),
                    label: const Text('Baixar Manualmente'),
                    onPressed: _openManualDownload,
                  ),
                  Row(
                    children: [
                      if (!_isDownloading)
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Mais Tarde'),
                        ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        icon: const Icon(Icons.download, size: 16),
                        label: Text(_isDownloading ? 'Instalando...' : 'Atualizar Agora'),
                        onPressed: _isDownloading ? null : _startUpdate,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

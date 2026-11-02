import 'dart:io';
import 'package:flutter/services.dart';

class NativeFilePickerResult {
  final String path;
  final String? bookmark;

  const NativeFilePickerResult({required this.path, this.bookmark});
}

class NativeFilePicker {
  static const MethodChannel _iosChannel =
      MethodChannel('openmoney/native_file_picker');

  static String _normalizeMacPosixPath(String raw) {
    var p = raw.trim();
    if (p.isEmpty) return '';
    // Caso o AppleScript retorne prefixo de volume HFS "/file NomeDoVolume/Users/..."
    final fileVolPrefix = RegExp(r'^/file [^/]+(/.*)$');
    final match = fileVolPrefix.firstMatch(p);
    if (match != null) {
      p = match.group(1)!;
    }
    final aliasVolPrefix = RegExp(r'^/alias [^/]+(/.*)$');
    final aliasMatch = aliasVolPrefix.firstMatch(p);
    if (aliasMatch != null) {
      p = aliasMatch.group(1)!;
    }
    return p;
  }

  static String _escapeAppleScript(String text) {
    return text.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  }

  static String _escapePowerShellString(String text) {
    return text
        .replaceAll('`', '``')
        .replaceAll('"', '`"')
        .replaceAll('\$', '`\$')
        .replaceAll("'", "''");
  }

  /// Converte extensões comuns em tipos e UTIs reconhecidos pelo macOS.
  static List<String> _resolveMacTypes(List<String> allowedExtensions) {
    final types = <String>{};
    for (final raw in allowedExtensions) {
      final ext = raw.trim().toLowerCase().replaceAll(RegExp(r'^\.+'), '');
      if (ext.isEmpty) continue;

      switch (ext) {
        case 'json':
          types.add('public.json');
          break;
        case 'csv':
          types.add('public.comma-separated-values-text');
          types.add('public.delimited-values-text');
          types.add('csv');
          break;
        case 'qif':
          types.add('qif');
          break;
        case 'zip':
          types.add('public.zip-archive');
          types.add('com.pkware.zip-archive');
          types.add('zip');
          break;
        case 'pdf':
          types.add('com.adobe.pdf');
          types.add('pdf');
          break;
        case 'txt':
          types.add('public.plain-text');
          types.add('txt');
          break;
        default:
          types.add(ext);
          break;
      }
    }
    return types.toList();
  }

  /// Abre janela nativa do sistema para selecionar arquivo existente (.json, .csv, .qif, etc.)
  static Future<String?> pickFile({
    String title = 'Escolher Arquivo',
    List<String> allowedExtensions = const ['json'],
  }) async {
    final res = await pickFileWithMetadata(
      title: title,
      allowedExtensions: allowedExtensions,
    );
    return res?.path;
  }

  /// Abre seletor com suporte a metadata (como bookmark de segurança no iOS/iPadOS)
  static Future<NativeFilePickerResult?> pickFileWithMetadata({
    String title = 'Escolher Arquivo',
    List<String> allowedExtensions = const ['json'],
  }) async {
    try {
      if (Platform.isIOS) {
        final res = await _iosChannel.invokeMethod<Map>('pickFile', {
          'title': title,
          'allowedExtensions': allowedExtensions,
        });
        if (res != null && res['path'] is String) {
          final p = (res['path'] as String).trim();
          if (p.isNotEmpty) {
            return NativeFilePickerResult(
              path: p,
              bookmark: res['bookmark'] as String?,
            );
          }
        }
        return null;
      } else if (Platform.isMacOS) {
        final macTypes = _resolveMacTypes(allowedExtensions);
        final ofTypeClause = macTypes.isNotEmpty
            ? ' of type {${macTypes.map((t) => '"${_escapeAppleScript(t)}"').join(', ')}}'
            : '';
        final escapedTitle = _escapeAppleScript(title);
        final script =
            'activate\nPOSIX path of (choose file with prompt "$escapedTitle"$ofTypeClause)';
        final res = await Process.run('osascript', ['-e', script]);
        if (res.exitCode == 0) {
          final posixPath = _normalizeMacPosixPath(res.stdout.toString());
          if (posixPath.isNotEmpty) {
            return NativeFilePickerResult(path: posixPath);
          }
        }
      } else if (Platform.isWindows) {
        final filter = allowedExtensions
            .map((e) => '*.${e.toLowerCase().replaceAll(RegExp(r'^\.+'), '')}')
            .join(';');
        final escapedTitle = _escapePowerShellString(title);
        final powershellCmd =
            'Add-Type -AssemblyName System.Windows.Forms; '
            '\$dlg = New-Object System.Windows.Forms.OpenFileDialog; '
            '\$dlg.Title = "$escapedTitle"; '
            '\$dlg.Filter = "Arquivos ($filter)|$filter|Todos os Arquivos (*.*)|*.*"; '
            'if (\$dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { \$dlg.FileName }';
        final res = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Sta',
          '-Command',
          powershellCmd,
        ]);
        if (res.exitCode == 0) {
          final out = res.stdout.toString().trim();
          if (out.isNotEmpty) {
            return NativeFilePickerResult(path: out);
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Abre janela nativa do sistema para escolher local e nome para salvar arquivo
  static Future<String?> saveFile({
    String title = 'Salvar Arquivo',
    String defaultName = 'openmoney.json',
    List<String> allowedExtensions = const ['json'],
  }) async {
    final res = await saveFileWithMetadata(
      title: title,
      defaultName: defaultName,
      allowedExtensions: allowedExtensions,
    );
    return res?.path;
  }

  /// Abre salvamento com suporte a metadata (como bookmark de segurança no iOS/iPadOS)
  static Future<NativeFilePickerResult?> saveFileWithMetadata({
    String title = 'Salvar Arquivo',
    String defaultName = 'openmoney.json',
    List<String> allowedExtensions = const ['json'],
  }) async {
    try {
      if (Platform.isIOS) {
        final res = await _iosChannel.invokeMethod<Map>('saveFile', {
          'title': title,
          'defaultName': defaultName,
          'allowedExtensions': allowedExtensions,
        });
        if (res != null && res['path'] is String) {
          final p = (res['path'] as String).trim();
          if (p.isNotEmpty) {
            return NativeFilePickerResult(
              path: p,
              bookmark: res['bookmark'] as String?,
            );
          }
        }
        return null;
      } else if (Platform.isMacOS) {
        final escapedTitle = _escapeAppleScript(title);
        final escapedDefault = _escapeAppleScript(defaultName);
        final script =
            'activate\nPOSIX path of (choose file name with prompt "$escapedTitle" default name "$escapedDefault")';
        final res = await Process.run('osascript', ['-e', script]);
        if (res.exitCode == 0) {
          var posixPath = _normalizeMacPosixPath(res.stdout.toString());
          if (posixPath.isNotEmpty) {
            final expectedExt = allowedExtensions.isNotEmpty
                ? allowedExtensions.first.toLowerCase().replaceAll(RegExp(r'^\.+'), '')
                : 'json';
            final hasAllowedExt = allowedExtensions.any(
              (ext) {
                final clean = ext.toLowerCase().replaceAll(RegExp(r'^\.+'), '');
                return posixPath.toLowerCase().endsWith('.$clean');
              },
            );
            if (!hasAllowedExt) {
              posixPath += '.$expectedExt';
            }
            return NativeFilePickerResult(path: posixPath);
          }
        }
      } else if (Platform.isWindows) {
        final filter = allowedExtensions
            .map((e) => '*.${e.toLowerCase().replaceAll(RegExp(r'^\.+'), '')}')
            .join(';');
        final escapedTitle = _escapePowerShellString(title);
        final escapedDefault = _escapePowerShellString(defaultName);
        final powershellCmd =
            'Add-Type -AssemblyName System.Windows.Forms; '
            '\$dlg = New-Object System.Windows.Forms.SaveFileDialog; '
            '\$dlg.Title = "$escapedTitle"; '
            '\$dlg.FileName = "$escapedDefault"; '
            '\$dlg.Filter = "Arquivos ($filter)|$filter|Todos os Arquivos (*.*)|*.*"; '
            'if (\$dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { \$dlg.FileName }';
        final res = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Sta',
          '-Command',
          powershellCmd,
        ]);
        if (res.exitCode == 0) {
          final out = res.stdout.toString().trim();
          if (out.isNotEmpty) {
            return NativeFilePickerResult(path: out);
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Abre janela nativa do sistema para escolher uma pasta (diretório)
  static Future<String?> pickFolder({
    String title = 'Selecionar Pasta de Comprovantes',
  }) async {
    try {
      if (Platform.isMacOS) {
        final escapedTitle = _escapeAppleScript(title);
        final script =
            'activate\nPOSIX path of (choose folder with prompt "$escapedTitle")';
        final res = await Process.run('osascript', ['-e', script]);
        if (res.exitCode == 0) {
          final posixPath = _normalizeMacPosixPath(res.stdout.toString());
          if (posixPath.isNotEmpty) return posixPath;
        }
      } else if (Platform.isWindows) {
        final escapedTitle = _escapePowerShellString(title);
        final powershellCmd =
            'Add-Type -AssemblyName System.Windows.Forms; '
            '\$dlg = New-Object System.Windows.Forms.FolderBrowserDialog; '
            '\$dlg.Description = "$escapedTitle"; '
            '\$dlg.ShowNewFolderButton = \$false; '
            'if (\$dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { \$dlg.SelectedPath }';
        final res = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Sta',
          '-Command',
          powershellCmd,
        ]);
        if (res.exitCode == 0) {
          final out = res.stdout.toString().trim();
          if (out.isNotEmpty) return out;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Restaura acesso a um arquivo via Security-Scoped Bookmark no iOS
  static Future<NativeFilePickerResult?> resolveIosBookmark(String bookmarkB64) async {
    if (!Platform.isIOS || bookmarkB64.isEmpty) return null;
    try {
      final res = await _iosChannel.invokeMethod<Map>('resolveBookmark', {
        'bookmark': bookmarkB64,
      });
      if (res != null && res['path'] is String) {
        final p = (res['path'] as String).trim();
        if (p.isNotEmpty) {
          return NativeFilePickerResult(
            path: p,
            bookmark: res['bookmark'] as String?,
          );
        }
      }
    } catch (_) {}
    return null;
  }

  /// Garante acesso security-scoped no iOS a partir do caminho se necessário
  static Future<void> startAccessingPath(String path) async {
    if (!Platform.isIOS || path.isEmpty) return;
    try {
      await _iosChannel.invokeMethod('startAccessingPath', {'path': path});
    } catch (_) {}
  }
}

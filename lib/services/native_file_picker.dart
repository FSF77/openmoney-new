import 'dart:io';

class NativeFilePicker {
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
  /// No macOS, o parâmetro `of type` do AppleScript espera UTIs (ex: 'public.json')
  /// ou códigos OSType clássicos de 4 caracteres. Se passar 'json', o sistema trata
  /// como OSType 'json' inexistente, deixando arquivos .json desabilitados (cinza claro)
  /// e exigindo duplo-clique. Ao usar 'public.json', os arquivos .json são habilitados
  /// com texto preto e selecionados com 1 clique único imediato.
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
    try {
      if (Platform.isMacOS) {
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
          if (posixPath.isNotEmpty) return posixPath;
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
          if (out.isNotEmpty) return out;
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
    try {
      if (Platform.isMacOS) {
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
            return posixPath;
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
          if (out.isNotEmpty) return out;
        }
      }
    } catch (_) {}
    return null;
  }
}

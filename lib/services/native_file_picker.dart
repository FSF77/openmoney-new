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

  /// Abre janela nativa do sistema para selecionar arquivo existente (.json, .csv, .qif, etc.)
  static Future<String?> pickFile({
    String title = 'Escolher Arquivo',
    List<String> allowedExtensions = const ['json'],
  }) async {
    try {
      if (Platform.isMacOS) {
        final exts = allowedExtensions.map((e) => '"$e"').join(', ');
        final script =
            'POSIX path of (choose file with prompt "$title" of type {$exts})';
        final res = await Process.run('osascript', ['-e', script]);
        if (res.exitCode == 0) {
          final posixPath = _normalizeMacPosixPath(res.stdout.toString());
          if (posixPath.isNotEmpty) return posixPath;
        }
      } else if (Platform.isWindows) {
        final filter = allowedExtensions.map((e) => '*.$e').join(';');
        final powershellCmd =
            '[System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null; '
            '\$dlg = New-Object System.Windows.Forms.OpenFileDialog; '
            '\$dlg.Title = "$title"; '
            '\$dlg.Filter = "Arquivos ($filter)|$filter|Todos os Arquivos (*.*)|*.*"; '
            'if (\$dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { \$dlg.FileName }';
        final res =
            await Process.run('powershell', ['-Command', powershellCmd]);
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
        final script =
            'POSIX path of (choose file name with prompt "$title" default name "$defaultName")';
        final res = await Process.run('osascript', ['-e', script]);
        if (res.exitCode == 0) {
          var posixPath = _normalizeMacPosixPath(res.stdout.toString());
          if (posixPath.isNotEmpty) {
            final expectedExt =
                allowedExtensions.isNotEmpty ? allowedExtensions.first : 'json';
            final hasAllowedExt = allowedExtensions.any(
              (ext) =>
                  posixPath.toLowerCase().endsWith('.${ext.toLowerCase()}'),
            );
            if (!hasAllowedExt) {
              posixPath += '.$expectedExt';
            }
            return posixPath;
          }
        }
      } else if (Platform.isWindows) {
        final filter = allowedExtensions.map((e) => '*.$e').join(';');
        final powershellCmd =
            '[System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null; '
            '\$dlg = New-Object System.Windows.Forms.SaveFileDialog; '
            '\$dlg.Title = "$title"; '
            '\$dlg.FileName = "$defaultName"; '
            '\$dlg.Filter = "Arquivos ($filter)|$filter|Todos os Arquivos (*.*)|*.*"; '
            'if (\$dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { \$dlg.FileName }';
        final res =
            await Process.run('powershell', ['-Command', powershellCmd]);
        if (res.exitCode == 0) {
          final out = res.stdout.toString().trim();
          if (out.isNotEmpty) return out;
        }
      }
    } catch (_) {}
    return null;
  }
}

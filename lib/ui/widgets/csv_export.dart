import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/native_file_picker.dart';

Future<void> exportCsvWithFeedback(
  BuildContext context, {
  required String csv,
  required String defaultName,
  required String title,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!kIsWeb) {
    try {
      final path = await NativeFilePicker.saveFile(
        title: title,
        defaultName: defaultName,
        allowedExtensions: ['csv'],
      );
      if (path == null || path.isEmpty) return;
      final f = File(path);
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(csv, flush: true);

      if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', path]);
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text('✓ CSV exportado com sucesso em:\n$path'),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Erro ao exportar CSV: $e'),
        backgroundColor: Colors.redAccent,
      ));
    }
    return;
  }
  Clipboard.setData(ClipboardData(text: csv));
  messenger.showSnackBar(
      const SnackBar(content: Text('✓ Lançamentos copiados em formato CSV!')));
}

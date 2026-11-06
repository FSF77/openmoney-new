import 'package:flutter/services.dart';
import 'platform_io.dart';

/// Serviço responsável por extrair texto de imagens e documentos PDF localmente,
/// utilizando os recursos nativos do sistema operacional (macOS Vision e Windows Media OCR / PowerShell).
class LocalOcrService {
  static const MethodChannel _macOcrChannel =
      MethodChannel('openmoney/native_ocr');

  /// Extrai o texto contido no arquivo (PDF ou imagem)
  static Future<String> extractText(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) return '';

    final ext = filePath.split('.').last.toLowerCase();

    if (Platform.isMacOS) {
      return _extractMac(filePath, ext);
    } else if (Platform.isWindows) {
      return _extractWindows(filePath, ext);
    }

    return '';
  }

  static Future<String> _extractMac(String filePath, String ext) async {
    try {
      // 1. Tenta canal nativo macOS se registrado
      final res = await _macOcrChannel.invokeMethod<String>('extractText', {
        'path': filePath,
      });
      if (res != null && res.trim().isNotEmpty) {
        return res.trim();
      }
    } catch (_) {}

    // 2. Fallback macOS via script Swift inline de alto desempenho utilizando PDFKit e Vision
    try {
      final script = '''
import Foundation
import PDFKit
import Vision
import AppKit

let path = "$filePath"
let url = URL(fileURLWithPath: path)
let ext = url.pathExtension.lowercased()

if ext == "pdf" {
    if let pdf = PDFDocument(url: url) {
        var fullText = ""
        for i in 0..<pdf.pageCount {
            if let page = pdf.page(at: i), let pageText = page.string {
                fullText += pageText + "\\n"
            }
        }
        if !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print(fullText)
            exit(0)
        }
    }
}

// Vision OCR para imagens ou PDFs sem texto vetorial
guard let image = NSImage(contentsOf: url),
      let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let cgImage = bitmap.cgImage else {
    exit(0)
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.recognitionLanguages = ["pt-BR", "en-US"]
request.usesLanguageCorrection = true

let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
try? handler.perform([request])

var recognized = ""
if let results = request.results {
    for obs in results {
        if let top = obs.topCandidates(1).first {
            recognized += top.string + "\\n"
        }
    }
}
print(recognized)
''';

      final res = await Process.run('swift', ['-e', script]);
      if (res.exitCode == 0) {
        return res.stdout.toString().trim();
      }
    } catch (_) {}

    return '';
  }

  static Future<String> _extractWindows(String filePath, String ext) async {
    try {
      // No Windows 10/11: extração via Windows.Media.Ocr nativo por PowerShell
      final escapedPath = filePath.replaceAll("'", "''");
      final psScript = '''
[Windows.Globalization.Language, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
[Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
[Windows.Storage.StorageFile, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null

Add-Type -AssemblyName System.Runtime.WindowsRuntime
\$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { \$_.Name -eq 'AsTask' -and \$_.GetParameters().Count -eq 1 -and \$_.IsGenericMethod })[0]

function Await(\$winRtTask, \$resultType) {
    \$asTask = \$asTaskGeneric.MakeGenericMethod(\$resultType)
    \$netTask = \$asTask.Invoke(\$null, @(\$winRtTask))
    \$netTask.Wait(-1) | Out-Null
    \$netTask.Result
}

try {
    \$file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync('$escapedPath')) ([Windows.Storage.StorageFile])
    \$stream = Await (\$file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
    \$decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync(\$stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
    \$bitmap = Await (\$decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
    
    \$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
    if (\$engine -eq \$null) {
        \$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage([Windows.Globalization.Language]::new("pt-BR"))
    }
    if (\$engine -eq \$null) {
        \$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage([Windows.Globalization.Language]::new("en-US"))
    }
    if (\$engine -ne \$null) {
        \$ocrResult = Await (\$engine.RecognizeAsync(\$bitmap)) ([Windows.Media.Ocr.OcrResult])
        Write-Output \$ocrResult.Text
    }
} catch {
}
''';

      final res = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Sta',
        '-Command',
        psScript,
      ]);

      if (res.exitCode == 0) {
        return res.stdout.toString().trim();
      }
    } catch (_) {}

    return '';
  }
}

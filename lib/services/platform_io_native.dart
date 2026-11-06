import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

export 'dart:io';

Future<String?> webPickFileAsVirtualPath({
  List<String> allowedExtensions = const ['json'],
}) async {
  return null;
}

String? webLocalStorageGet(String key) => null;

void webLocalStorageSet(String key, String value) {}

void webLocalStorageRemove(String key) {}

String webWindowOrigin() => '';

void webOpenExternalUrl(String url) {
  try {
    if (Platform.isMacOS) {
      Process.run('open', [url]);
    } else if (Platform.isWindows) {
      Process.run('cmd', ['/c', 'start', '', url]);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [url]);
    }
  } catch (_) {}
}

void triggerBrowserDownloadBytes({
  required List<int> bytes,
  required String filename,
  String mimeType = 'application/octet-stream',
}) {}

Future<({int statusCode, String body})> platformHttpRequest({
  required String method,
  required String url,
  Map<String, String>? headers,
  String? body,
  Duration timeout = const Duration(seconds: 25),
}) async {
  final client = HttpClient();
  client.connectionTimeout = timeout;
  try {
    final uri = Uri.parse(url);
    final req = await client.openUrl(method.toUpperCase(), uri).timeout(timeout);
    req.headers.set('Accept', 'application/json');
    if (headers != null) {
      headers.forEach((k, v) {
        req.headers.set(k, v);
      });
    }
    if (body != null && body.isNotEmpty) {
      final encoded = utf8.encode(body);
      req.contentLength = encoded.length;
      req.add(encoded);
    }
    final res = await req.close().timeout(timeout);
    final resBody = await res.transform(utf8.decoder).join().timeout(timeout);
    return (statusCode: res.statusCode, body: resBody);
  } finally {
    client.close();
  }
}

Future<Uint8List> platformGzipCompress(Uint8List rawBytes) async {
  return Uint8List.fromList(gzip.encode(rawBytes));
}

Future<Uint8List> platformGzipDecompress(Uint8List compressedBytes) async {
  return Uint8List.fromList(gzip.decode(compressedBytes));
}

Future<({int statusCode, Uint8List bodyBytes, Map<String, String> headers})>
    platformHttpBinaryRequest({
  required String method,
  required String url,
  Map<String, String>? headers,
  Uint8List? bodyBytes,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final client = HttpClient();
  client.connectionTimeout = timeout;
  client.autoUncompress = false;
  try {
    final uri = Uri.parse(url);
    final req = await client.openUrl(method.toUpperCase(), uri).timeout(timeout);
    if (headers != null) {
      headers.forEach((k, v) {
        req.headers.set(k, v);
      });
    }
    if (bodyBytes != null && bodyBytes.isNotEmpty) {
      req.contentLength = bodyBytes.length;
      req.add(bodyBytes);
    }
    final res = await req.close().timeout(timeout);
    final chunks = <int>[];
    await for (final chunk in res.timeout(timeout)) {
      chunks.addAll(chunk);
    }
    final respHeaders = <String, String>{};
    res.headers.forEach((name, values) {
      if (values.isNotEmpty) {
        respHeaders[name.toLowerCase()] = values.first;
      }
    });
    return (
      statusCode: res.statusCode,
      bodyBytes: Uint8List.fromList(chunks),
      headers: respHeaders,
    );
  } finally {
    client.close();
  }
}

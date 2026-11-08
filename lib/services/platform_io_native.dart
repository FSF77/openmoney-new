import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

export 'dart:io';

Future<String?> webPickFileAsVirtualPath({
  List<String> allowedExtensions = const ['json'],
}) async {
  return null;
}

String _getAppSupportDir() {
  final sep = Platform.pathSeparator;
  String baseDir;
  if (Platform.isWindows) {
    baseDir = Platform.environment['APPDATA'] ??
        '${Platform.environment['USERPROFILE'] ?? '.'}${sep}AppData${sep}Roaming';
  } else if (Platform.isMacOS) {
    final home = Platform.environment['HOME'] ?? '.';
    baseDir = '$home/Library/Application Support';
  } else if (Platform.isIOS) {
    final home = Platform.environment['HOME'] ?? '.';
    baseDir = '$home/Documents';
  } else {
    final home = Platform.environment['HOME'] ?? '.';
    baseDir = '$home/.local/share';
  }
  final dir = Directory('$baseDir${sep}OpenMoneyNew');
  if (!dir.existsSync()) {
    try {
      dir.createSync(recursive: true);
    } catch (_) {}
  }
  return dir.path;
}

Map<String, String>? _nativeKvCache;
File? _nativeKvFile;

void _ensureNativeKvLoaded() {
  if (_nativeKvCache != null) return;
  _nativeKvCache = <String, String>{};
  try {
    final dir = _getAppSupportDir();
    _nativeKvFile = File('$dir${Platform.pathSeparator}sync_kv_store.json');
    if (_nativeKvFile!.existsSync()) {
      final raw = _nativeKvFile!.readAsStringSync();
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((k, v) {
          if (v != null) _nativeKvCache![k.toString()] = v.toString();
        });
      }
    }
  } catch (_) {}
}

void _flushNativeKv() {
  try {
    if (_nativeKvFile != null && _nativeKvCache != null) {
      _nativeKvFile!.writeAsStringSync(jsonEncode(_nativeKvCache), flush: true);
    }
  } catch (_) {}
}

String? webLocalStorageGet(String key) {
  _ensureNativeKvLoaded();
  return _nativeKvCache?[key];
}

void webLocalStorageSet(String key, String value) {
  _ensureNativeKvLoaded();
  _nativeKvCache?[key] = value;
  _flushNativeKv();
}

void webLocalStorageRemove(String key) {
  _ensureNativeKvLoaded();
  _nativeKvCache?.remove(key);
  _flushNativeKv();
}

String webWindowOrigin() => '';

String webWindowSearch() => '';

String webWindowHash() => '';

void webClearUrlQueryParams() {}

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
  client.autoUncompress = true;
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

bool webIsOnline() => true;

bool webIsDocumentVisible() => true;

void registerWebSyncListeners({
  required void Function() onOnline,
  required void Function() onOffline,
  required void Function() onVisibleOrFocus,
  required void Function(String data) onBroadcastMessage,
}) {}

void broadcastWebSyncSignal(String message) {}

class PlatformWebSocket {
  WebSocket? _ws;
  StreamSubscription? _sub;
  bool _closedByClient = false;

  PlatformWebSocket._();

  static PlatformWebSocket? connect(
    String wsUrl, {
    required void Function() onOpen,
    required void Function(String message) onMessage,
    required void Function() onClose,
  }) {
    final wrapper = PlatformWebSocket._();
    () async {
      try {
        final uri = Uri.parse(wsUrl);
        final ws = await WebSocket.connect(uri.toString())
            .timeout(const Duration(seconds: 15));
        if (wrapper._closedByClient) {
          try {
            ws.close();
          } catch (_) {}
          return;
        }
        ws.pingInterval = const Duration(seconds: 20);
        wrapper._ws = ws;
        onOpen();

        wrapper._sub = ws.listen(
          (data) {
            if (wrapper._closedByClient) return;
            if (data is String) {
              onMessage(data);
            } else if (data is List<int>) {
              onMessage(utf8.decode(data));
            }
          },
          onError: (_) {
            if (!wrapper._closedByClient) {
              wrapper.close();
              onClose();
            }
          },
          onDone: () {
            if (!wrapper._closedByClient) {
              wrapper.close();
              onClose();
            }
          },
          cancelOnError: true,
        );
      } catch (_) {
        if (!wrapper._closedByClient) {
          onClose();
        }
      }
    }();
    return wrapper;
  }

  bool get isOpen {
    if (_closedByClient || _ws == null) return false;
    return _ws!.readyState == WebSocket.open;
  }

  void send(String message) {
    try {
      if (isOpen) {
        _ws?.add(message);
      }
    } catch (_) {}
  }

  void close() {
    _closedByClient = true;
    try {
      _sub?.cancel();
    } catch (_) {}
    _sub = null;
    try {
      _ws?.close();
    } catch (_) {}
    _ws = null;
  }
}

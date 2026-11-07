import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

// Memória virtual para arquivos selecionados ou salvos durante a sessão Web
final Map<String, Uint8List> _webVirtualFiles = <String, Uint8List>{};
final Map<String, DateTime> _webVirtualFileModified = <String, DateTime>{};

@JS('window')
external JSObject get _window;

@JS('document')
external JSObject get _document;

@JS('URL')
external JSObject get _urlClass;

String webWindowOrigin() {
  try {
    final loc = _window.getProperty<JSObject?>('location'.toJS);
    if (loc != null) {
      final origin = loc.getProperty<JSString?>('origin'.toJS)?.toDart ?? '';
      return origin;
    }
  } catch (_) {}
  return '';
}

String webWindowSearch() {
  try {
    final loc = _window.getProperty<JSObject?>('location'.toJS);
    if (loc != null) {
      return loc.getProperty<JSString?>('search'.toJS)?.toDart ?? '';
    }
  } catch (_) {}
  return '';
}

String webWindowHash() {
  try {
    final loc = _window.getProperty<JSObject?>('location'.toJS);
    if (loc != null) {
      return loc.getProperty<JSString?>('hash'.toJS)?.toDart ?? '';
    }
  } catch (_) {}
  return '';
}

void webClearUrlQueryParams() {
  try {
    final loc = _window.getProperty<JSObject?>('location'.toJS);
    final history = _window.getProperty<JSObject?>('history'.toJS);
    if (loc != null && history != null) {
      final pathname =
          loc.getProperty<JSString?>('pathname'.toJS)?.toDart ?? '/';
      final hash = loc.getProperty<JSString?>('hash'.toJS)?.toDart ?? '';
      final cleanHash = hash.contains('?') ? hash.split('?').first : hash;
      final currentState = history.getProperty<JSAny?>('state'.toJS);
      history.callMethod<JSAny?>(
        'replaceState'.toJS,
        currentState,
        ''.toJS,
        '$pathname$cleanHash'.toJS,
      );
    }
  } catch (_) {}
}

String? webLocalStorageGet(String key) {
  try {
    final storage = _window.getProperty<JSObject?>('localStorage'.toJS);
    if (storage == null) return null;
    final res = storage.callMethod<JSString?>('getItem'.toJS, key.toJS);
    return res?.toDart;
  } catch (_) {
    return null;
  }
}

void webLocalStorageSet(String key, String value) {
  try {
    final storage = _window.getProperty<JSObject?>('localStorage'.toJS);
    if (storage == null) return;
    storage.callMethod<JSAny?>('setItem'.toJS, key.toJS, value.toJS);
  } catch (_) {}
}

void webLocalStorageRemove(String key) {
  try {
    final storage = _window.getProperty<JSObject?>('localStorage'.toJS);
    if (storage == null) return;
    storage.callMethod<JSAny?>('removeItem'.toJS, key.toJS);
  } catch (_) {}
}

void webOpenExternalUrl(String url) {
  try {
    _window.callMethod<JSAny?>('open'.toJS, url.toJS, '_blank'.toJS);
  } catch (_) {}
}

void triggerBrowserDownloadBytes({
  required List<int> bytes,
  required String filename,
  String mimeType = 'application/octet-stream',
}) {
  try {
    final uint8 = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final jsUint8 = uint8.toJS;
    final parts = <JSAny?>[jsUint8].toJS;
    final opts = JSObject();
    opts.setProperty('type'.toJS, mimeType.toJS);

    final blobCtor = _window.getProperty<JSFunction>('Blob'.toJS);
    final blob = blobCtor.callAsConstructor<JSObject>(parts, opts);
    final objectUrl =
        _urlClass.callMethod<JSString>('createObjectURL'.toJS, blob).toDart;

    final anchor = _document.callMethod<JSObject>('createElement'.toJS, 'a'.toJS);
    anchor.setProperty('href'.toJS, objectUrl.toJS);
    anchor.setProperty('download'.toJS, filename.toJS);
    anchor.setProperty('style'.toJS, 'display:none'.toJS);

    final body = _document.getProperty<JSObject?>('body'.toJS);
    body?.callMethod<JSAny?>('appendChild'.toJS, anchor);
    anchor.callMethod<JSAny?>('click'.toJS);
    body?.callMethod<JSAny?>('removeChild'.toJS, anchor);

    Future.delayed(const Duration(seconds: 2), () {
      try {
        _urlClass.callMethod<JSAny?>('revokeObjectURL'.toJS, objectUrl.toJS);
      } catch (_) {}
    });
  } catch (_) {}
}

Future<String?> webPickFileAsVirtualPath({
  List<String> allowedExtensions = const ['json'],
}) async {
  final completer = Completer<String?>();
  try {
    final input =
        _document.callMethod<JSObject>('createElement'.toJS, 'input'.toJS);
    input.setProperty('type'.toJS, 'file'.toJS);
    input.setProperty('style'.toJS, 'display:none'.toJS);
    if (allowedExtensions.isNotEmpty) {
      final accept = allowedExtensions
          .map((e) => '.${e.toLowerCase().replaceAll(RegExp(r'^\.+'), '')}')
          .join(',');
      input.setProperty('accept'.toJS, accept.toJS);
    }

    final body = _document.getProperty<JSObject?>('body'.toJS);
    body?.callMethod<JSAny?>('appendChild'.toJS, input);

    bool completed = false;
    void finish(String? result) {
      if (!completed) {
        completed = true;
        try {
          body?.callMethod<JSAny?>('removeChild'.toJS, input);
        } catch (_) {}
        completer.complete(result);
      }
    }

    input.setProperty(
      'oncancel'.toJS,
      ((JSAny? _) {
        finish(null);
      }).toJS,
    );

    input.setProperty(
      'onchange'.toJS,
      ((JSAny? _) {
        try {
          final files = input.getProperty<JSObject?>('files'.toJS);
          if (files == null) {
            finish(null);
            return;
          }
          final length =
              files.getProperty<JSNumber?>('length'.toJS)?.toDartInt ?? 0;
          if (length <= 0) {
            finish(null);
            return;
          }
          final file = files.callMethod<JSObject?>('item'.toJS, 0.toJS);
          if (file == null) {
            finish(null);
            return;
          }
          final fileName =
              file.getProperty<JSString?>('name'.toJS)?.toDart ?? 'arquivo.dat';

          final readerCtor = _window.getProperty<JSFunction>('FileReader'.toJS);
          final reader = readerCtor.callAsConstructor<JSObject>();

          reader.setProperty(
            'onload'.toJS,
            ((JSAny? __) {
              try {
                final result = reader.getProperty<JSAny?>('result'.toJS);
                if (result != null) {
                  final uint8Ctor =
                      _window.getProperty<JSFunction>('Uint8Array'.toJS);
                  final jsUint8 =
                      uint8Ctor.callAsConstructor<JSUint8Array>(result);
                  final bytes = jsUint8.toDart;
                  final virtualPath = 'web://picked/$fileName';
                  _webVirtualFiles[virtualPath] = bytes;
                  _webVirtualFileModified[virtualPath] = DateTime.now();
                  finish(virtualPath);
                  return;
                }
              } catch (_) {}
              finish(null);
            }).toJS,
          );

          reader.setProperty(
            'onerror'.toJS,
            ((JSAny? __) {
              finish(null);
            }).toJS,
          );

          reader.callMethod<JSAny?>('readAsArrayBuffer'.toJS, file);
        } catch (_) {
          finish(null);
        }
      }).toJS,
    );

    input.callMethod<JSAny?>('click'.toJS);
  } catch (_) {
    if (!completer.isCompleted) completer.complete(null);
  }
  return completer.future;
}

Future<({int statusCode, String body})> platformHttpRequest({
  required String method,
  required String url,
  Map<String, String>? headers,
  String? body,
  Duration timeout = const Duration(seconds: 45),
}) async {
  final init = JSObject();
  init.setProperty('method'.toJS, method.toUpperCase().toJS);

  final jsHeaders = JSObject();
  jsHeaders.setProperty('Accept'.toJS, 'application/json'.toJS);
  if (headers != null) {
    headers.forEach((k, v) {
      jsHeaders.setProperty(k.toJS, v.toJS);
    });
  }
  init.setProperty('headers'.toJS, jsHeaders);

  if (body != null && body.isNotEmpty && method.toUpperCase() != 'GET') {
    init.setProperty('body'.toJS, body.toJS);
  }

  final fetchPromise =
      _window.callMethod<JSPromise<JSObject>>('fetch'.toJS, url.toJS, init);
  final response = await fetchPromise.toDart.timeout(timeout);
  final status =
      response.getProperty<JSNumber?>('status'.toJS)?.toDartInt ?? 500;
  final textPromise = response.callMethod<JSPromise<JSString>>('text'.toJS);
  final text = (await textPromise.toDart.timeout(timeout)).toDart;
  return (statusCode: status, body: text);
}

Future<Uint8List> platformGzipCompress(Uint8List rawBytes) async {
  try {
    final jsUint8 = rawBytes.toJS;
    final parts = <JSAny?>[jsUint8].toJS;
    final blobCtor = _window.getProperty<JSFunction>('Blob'.toJS);
    final blob = blobCtor.callAsConstructor<JSObject>(parts);
    final stream = blob.callMethod<JSObject>('stream'.toJS);
    final csCtor = _window.getProperty<JSFunction>('CompressionStream'.toJS);
    final cs = csCtor.callAsConstructor<JSObject>('gzip'.toJS);
    final compressedStream =
        stream.callMethod<JSObject>('pipeThrough'.toJS, cs);
    final respCtor = _window.getProperty<JSFunction>('Response'.toJS);
    final resp = respCtor.callAsConstructor<JSObject>(compressedStream);
    final bufPromise =
        resp.callMethod<JSPromise<JSArrayBuffer>>('arrayBuffer'.toJS);
    final buf = await bufPromise.toDart;
    return buf.toDart.asUint8List();
  } catch (_) {
    return rawBytes;
  }
}

Future<Uint8List> platformGzipDecompress(Uint8List compressedBytes) async {
  try {
    final jsUint8 = compressedBytes.toJS;
    final parts = <JSAny?>[jsUint8].toJS;
    final blobCtor = _window.getProperty<JSFunction>('Blob'.toJS);
    final blob = blobCtor.callAsConstructor<JSObject>(parts);
    final stream = blob.callMethod<JSObject>('stream'.toJS);
    final dsCtor =
        _window.getProperty<JSFunction>('DecompressionStream'.toJS);
    final ds = dsCtor.callAsConstructor<JSObject>('gzip'.toJS);
    final decompressedStream =
        stream.callMethod<JSObject>('pipeThrough'.toJS, ds);
    final respCtor = _window.getProperty<JSFunction>('Response'.toJS);
    final resp = respCtor.callAsConstructor<JSObject>(decompressedStream);
    final bufPromise =
        resp.callMethod<JSPromise<JSArrayBuffer>>('arrayBuffer'.toJS);
    final buf = await bufPromise.toDart;
    return buf.toDart.asUint8List();
  } catch (_) {
    return compressedBytes;
  }
}

Future<({int statusCode, Uint8List bodyBytes, Map<String, String> headers})>
    platformHttpBinaryRequest({
  required String method,
  required String url,
  Map<String, String>? headers,
  Uint8List? bodyBytes,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final init = JSObject();
  init.setProperty('method'.toJS, method.toUpperCase().toJS);

  final jsHeaders = JSObject();
  if (headers != null) {
    headers.forEach((k, v) {
      jsHeaders.setProperty(k.toJS, v.toJS);
    });
  }
  init.setProperty('headers'.toJS, jsHeaders);

  if (bodyBytes != null &&
      bodyBytes.isNotEmpty &&
      method.toUpperCase() != 'GET') {
    init.setProperty('body'.toJS, bodyBytes.toJS);
  }

  final fetchPromise =
      _window.callMethod<JSPromise<JSObject>>('fetch'.toJS, url.toJS, init);
  final response = await fetchPromise.toDart.timeout(timeout);
  final status =
      response.getProperty<JSNumber?>('status'.toJS)?.toDartInt ?? 500;

  final respHeaders = <String, String>{};
  final rawHeaders = response.getProperty<JSObject?>('headers'.toJS);
  if (rawHeaders != null) {
    const knownKeys = [
      'content-type',
      'x-openmoney-compression',
      'x-openmoney-revision',
      'x-openmoney-updated-at',
      'x-openmoney-prefs',
    ];
    for (final k in knownKeys) {
      final val = rawHeaders.callMethod<JSString?>('get'.toJS, k.toJS)?.toDart;
      if (val != null && val.isNotEmpty) {
        respHeaders[k] = val;
      }
    }
  }

  final bufPromise =
      response.callMethod<JSPromise<JSArrayBuffer>>('arrayBuffer'.toJS);
  final buf = (await bufPromise.toDart.timeout(timeout)).toDart;
  return (
    statusCode: status,
    bodyBytes: buf.asUint8List(),
    headers: respHeaders,
  );
}

// ============================================================================
// Shims de compatibilidade com dart:io para compilação limpa no Flutter Web
// ============================================================================

class Platform {
  static const bool isWindows = false;
  static const bool isMacOS = false;
  static const bool isLinux = false;
  static const bool isAndroid = false;
  static const bool isIOS = false;
  static const String pathSeparator = '/';
  static const String operatingSystem = 'web';
  static const String resolvedExecutable = '';
  static const Map<String, String> environment = <String, String>{};
}

class FileMode {
  const FileMode._();
  static const FileMode read = FileMode._();
  static const FileMode write = FileMode._();
  static const FileMode append = FileMode._();
  static const FileMode writeOnly = FileMode._();
  static const FileMode writeOnlyAppend = FileMode._();
}

class FileStat {
  final DateTime modified;
  final int size;
  const FileStat({required this.modified, required this.size});
}

class FileSystemEvent {
  static const int create = 1;
  static const int modify = 2;
  static const int delete = 4;
  static const int move = 8;
  static const int all = 15;

  final String path;
  final int type;
  const FileSystemEvent(this.path, [this.type = modify]);
}

abstract class FileSystemEntity {
  String get path;
  Uri get uri => Uri.parse(path);

  Directory get parent {
    final idx = path.lastIndexOf('/');
    if (idx <= 0) return Directory('');
    return Directory(path.substring(0, idx));
  }

  FileSystemEntity get absolute => this;
}

class Directory extends FileSystemEntity {
  @override
  final String path;

  Directory(this.path);

  static Directory get systemTemp => Directory('/tmp');

  bool existsSync() => false;
  Future<bool> exists() async => false;

  void createSync({bool recursive = false}) {}
  Future<Directory> create({bool recursive = false}) async => this;

  Directory createTempSync([String? prefix]) => Directory('/tmp/${prefix ?? "tmp"}');

  void deleteSync({bool recursive = false}) {}
  Future<FileSystemEntity> delete({bool recursive = false}) async => this;

  List<FileSystemEntity> listSync({
    bool recursive = false,
    bool followLinks = true,
  }) =>
      const <FileSystemEntity>[];

  Stream<FileSystemEvent> watch({
    int events = FileSystemEvent.all,
    bool recursive = false,
  }) =>
      const Stream<FileSystemEvent>.empty();
}

class File extends FileSystemEntity {
  @override
  final String path;

  File(this.path);

  @override
  File get absolute => this;

  @override
  Uri get uri {
    final clean = path.replaceAll('\\', '/');
    final parts = clean.split('/');
    return Uri(pathSegments: parts.where((p) => p.isNotEmpty).toList());
  }

  bool existsSync() => _webVirtualFiles.containsKey(path);
  Future<bool> exists() async => existsSync();

  DateTime lastModifiedSync() =>
      _webVirtualFileModified[path] ?? DateTime.now();

  FileStat statSync() {
    final bytes = _webVirtualFiles[path];
    return FileStat(
      modified: _webVirtualFileModified[path] ?? DateTime.now(),
      size: bytes?.length ?? 0,
    );
  }

  Uint8List readAsBytesSync() => _webVirtualFiles[path] ?? Uint8List(0);
  Future<Uint8List> readAsBytes() async => readAsBytesSync();

  String readAsStringSync({Encoding encoding = utf8}) {
    final bytes = _webVirtualFiles[path];
    if (bytes == null) return '';
    String decoded;
    if (encoding == utf8) {
      decoded = utf8.decode(bytes, allowMalformed: true);
    } else {
      decoded = encoding.decode(bytes);
    }
    if (decoded.startsWith('\uFEFF')) {
      return decoded.substring(1);
    }
    return decoded;
  }

  Future<String> readAsString({Encoding encoding = utf8}) async =>
      readAsStringSync(encoding: encoding);

  Future<List<String>> readAsLines({Encoding encoding = utf8}) async {
    final str = readAsStringSync(encoding: encoding);
    if (str.isEmpty) return <String>[];
    return const LineSplitter().convert(str);
  }

  void _maybeTriggerBrowserDownload(Uint8List bytes) {
    if (path.startsWith('web://download/') ||
        !path.startsWith('web://picked/')) {
      final clean = path.replaceAll('\\', '/');
      final filename = clean.split('/').last.isEmpty
          ? 'openmoney-export.dat'
          : clean.split('/').last;
      String mime = 'application/octet-stream';
      final lower = filename.toLowerCase();
      if (lower.endsWith('.json')) {
        mime = 'application/json;charset=utf-8';
      } else if (lower.endsWith('.csv')) {
        mime = 'text/csv;charset=utf-8';
      } else if (lower.endsWith('.pdf')) {
        mime = 'application/pdf';
      } else if (lower.endsWith('.qif')) {
        mime = 'application/qif;charset=utf-8';
      }
      triggerBrowserDownloadBytes(
        bytes: bytes,
        filename: filename,
        mimeType: mime,
      );
    }
  }

  void writeAsBytesSync(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    _webVirtualFiles[path] = data;
    _webVirtualFileModified[path] = DateTime.now();
    _maybeTriggerBrowserDownload(data);
  }

  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async {
    writeAsBytesSync(bytes, mode: mode, flush: flush);
    return this;
  }

  void writeAsStringSync(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) {
    final encoded = Uint8List.fromList(encoding.encode(contents));
    if (mode == FileMode.append || mode == FileMode.writeOnlyAppend) {
      final prev = _webVirtualFiles[path];
      if (prev != null && prev.isNotEmpty) {
        final merged = Uint8List(prev.length + encoded.length);
        merged.setRange(0, prev.length, prev);
        merged.setRange(prev.length, merged.length, encoded);
        _webVirtualFiles[path] = merged;
        _webVirtualFileModified[path] = DateTime.now();
        return;
      }
    }
    _webVirtualFiles[path] = encoded;
    _webVirtualFileModified[path] = DateTime.now();
    if (mode == FileMode.write || mode == FileMode.writeOnly) {
      _maybeTriggerBrowserDownload(encoded);
    }
  }

  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    writeAsStringSync(contents, mode: mode, encoding: encoding, flush: flush);
    return this;
  }

  File copySync(String newPath) {
    final bytes = _webVirtualFiles[path];
    if (bytes != null) {
      _webVirtualFiles[newPath] = Uint8List.fromList(bytes);
      _webVirtualFileModified[newPath] = DateTime.now();
    }
    return File(newPath);
  }

  File renameSync(String newPath) {
    final bytes = _webVirtualFiles.remove(path);
    if (bytes != null) {
      _webVirtualFiles[newPath] = bytes;
      _webVirtualFileModified[newPath] = DateTime.now();
    }
    return File(newPath);
  }

  IOSink openWrite({FileMode mode = FileMode.write, Encoding encoding = utf8}) {
    return IOSink(this);
  }

  Future<File> rename(String newPath) async {
    final bytes = _webVirtualFiles.remove(path);
    if (bytes != null) {
      _webVirtualFiles[newPath] = bytes;
      _webVirtualFileModified[newPath] = DateTime.now();
    }
    return File(newPath);
  }

  void deleteSync({bool recursive = false}) {
    _webVirtualFiles.remove(path);
    _webVirtualFileModified.remove(path);
  }

  Future<FileSystemEntity> delete({bool recursive = false}) async {
    deleteSync(recursive: recursive);
    return this;
  }
}

class IOSink implements StreamConsumer<List<int>> {
  final File _file;
  final List<int> _buffer = <int>[];

  IOSink([File? file]) : _file = file ?? File('');

  void add(List<int> data) {
    _buffer.addAll(data);
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      _buffer.addAll(chunk);
    }
  }

  Future<void> flush() async {}

  Future<void> close() async {
    if (_file.path.isNotEmpty) {
      _file.writeAsBytesSync(_buffer);
    }
  }
}

int get pid => 0;

class ProcessResult {
  final int pid;
  final int exitCode;
  final dynamic stdout;
  final dynamic stderr;
  const ProcessResult(this.pid, this.exitCode, this.stdout, this.stderr);
}

class Process {
  int get pid => 0;
  Future<int> get exitCode async => 0;

  static Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding = utf8,
    Encoding? stderrEncoding = utf8,
  }) async {
    return const ProcessResult(0, 1, '', 'Unsupported on Web');
  }

  static Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) async {
    return Process();
  }
}

class ProcessStartMode {
  const ProcessStartMode._();
  static const ProcessStartMode normal = ProcessStartMode._();
  static const ProcessStartMode inheritStdio = ProcessStartMode._();
  static const ProcessStartMode detached = ProcessStartMode._();
  static const ProcessStartMode detachedWithStdio = ProcessStartMode._();
}

void exit(int code) {}

// HttpClient shim para Web usando window.fetch
class HttpHeaders {
  static const String locationHeader = 'location';
  final Map<String, String> _headers = <String, String>{};

  void set(String name, Object value) {
    _headers[name.toLowerCase()] = value.toString();
  }

  String? value(String name) {
    return _headers[name.toLowerCase()];
  }
}

class HttpClientRequest {
  final String method;
  final Uri uri;
  final HttpHeaders headers = HttpHeaders();
  final List<int> _bodyBytes = <int>[];
  int contentLength = 0;

  HttpClientRequest(this.method, this.uri);

  void add(List<int> data) {
    _bodyBytes.addAll(data);
  }

  Future<HttpClientResponse> close() async {
    final bodyStr = _bodyBytes.isNotEmpty ? utf8.decode(_bodyBytes) : null;
    final res = await platformHttpRequest(
      method: method,
      url: uri.toString(),
      headers: headers._headers,
      body: bodyStr,
    );
    final respHeaders = HttpHeaders();
    return HttpClientResponse(res.statusCode, utf8.encode(res.body), respHeaders);
  }
}

class HttpClientResponse extends Stream<List<int>> {
  final int statusCode;
  final int contentLength;
  final List<int> _bytes;
  final HttpHeaders headers;

  HttpClientResponse(this.statusCode, this._bytes, [HttpHeaders? headers])
      : contentLength = _bytes.length,
        headers = headers ?? HttpHeaders();

  bool get isRedirect =>
      statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable(<List<int>>[_bytes]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

class HttpClient {
  Duration? connectionTimeout;

  Future<HttpClientRequest> getUrl(Uri url) async =>
      HttpClientRequest('GET', url);

  Future<HttpClientRequest> postUrl(Uri url) async =>
      HttpClientRequest('POST', url);

  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      HttpClientRequest(method, url);

  void close({bool force = false}) {}
}

bool webIsOnline() {
  try {
    final nav = _window.getProperty<JSObject?>('navigator'.toJS);
    if (nav != null) {
      final online = nav.getProperty<JSBoolean?>('onLine'.toJS)?.toDart;
      if (online != null) return online;
    }
  } catch (_) {}
  return true;
}

bool webIsDocumentVisible() {
  try {
    final state =
        _document.getProperty<JSString?>('visibilityState'.toJS)?.toDart;
    if (state != null) {
      return state != 'hidden';
    }
  } catch (_) {}
  return true;
}

JSObject? _broadcastChannel;
bool _webSyncListenersRegistered = false;

void registerWebSyncListeners({
  required void Function() onOnline,
  required void Function() onOffline,
  required void Function() onVisibleOrFocus,
  required void Function(String data) onBroadcastMessage,
}) {
  if (_webSyncListenersRegistered) return;
  _webSyncListenersRegistered = true;

  try {
    _window.callMethod<JSAny?>(
      'addEventListener'.toJS,
      'online'.toJS,
      ((JSAny? _) {
        onOnline();
      }).toJS,
    );
    _window.callMethod<JSAny?>(
      'addEventListener'.toJS,
      'offline'.toJS,
      ((JSAny? _) {
        onOffline();
      }).toJS,
    );
    _window.callMethod<JSAny?>(
      'addEventListener'.toJS,
      'focus'.toJS,
      ((JSAny? _) {
        onVisibleOrFocus();
      }).toJS,
    );
    _document.callMethod<JSAny?>(
      'addEventListener'.toJS,
      'visibilitychange'.toJS,
      ((JSAny? _) {
        if (webIsDocumentVisible()) {
          onVisibleOrFocus();
        }
      }).toJS,
    );
  } catch (_) {}

  try {
    final bcCtor = _window.getProperty<JSFunction?>('BroadcastChannel'.toJS);
    if (bcCtor != null) {
      _broadcastChannel =
          bcCtor.callAsConstructor<JSObject>('openmoney_sync_v2'.toJS);
      _broadcastChannel?.setProperty(
        'onmessage'.toJS,
        ((JSObject event) {
          try {
            final msg = event.getProperty<JSString?>('data'.toJS)?.toDart;
            if (msg != null && msg.isNotEmpty) {
              onBroadcastMessage(msg);
            }
          } catch (_) {}
        }).toJS,
      );
    }
  } catch (_) {}
}

void broadcastWebSyncSignal(String message) {
  try {
    _broadcastChannel?.callMethod<JSAny?>('postMessage'.toJS, message.toJS);
  } catch (_) {}
}

class PlatformWebSocket {
  JSObject? _ws;
  bool _closedByClient = false;

  PlatformWebSocket._(this._ws);

  static PlatformWebSocket? connect(
    String wsUrl, {
    required void Function() onOpen,
    required void Function(String message) onMessage,
    required void Function() onClose,
  }) {
    try {
      final wsCtor = _window.getProperty<JSFunction?>('WebSocket'.toJS);
      if (wsCtor == null) return null;
      final wsObj = wsCtor.callAsConstructor<JSObject>(wsUrl.toJS);
      final wrapper = PlatformWebSocket._(wsObj);

      wsObj.setProperty(
        'onopen'.toJS,
        ((JSAny? _) {
          if (!wrapper._closedByClient) onOpen();
        }).toJS,
      );

      wsObj.setProperty(
        'onmessage'.toJS,
        ((JSObject event) {
          if (wrapper._closedByClient) return;
          try {
            final data = event.getProperty<JSString?>('data'.toJS)?.toDart;
            if (data != null && data.isNotEmpty) {
              onMessage(data);
            }
          } catch (_) {}
        }).toJS,
      );

      wsObj.setProperty(
        'onclose'.toJS,
        ((JSAny? _) {
          if (!wrapper._closedByClient) onClose();
        }).toJS,
      );

      wsObj.setProperty(
        'onerror'.toJS,
        ((JSAny? _) {
          // onclose será chamado em seguida pelo navegador
        }).toJS,
      );

      return wrapper;
    } catch (_) {
      return null;
    }
  }

  bool get isOpen {
    try {
      if (_ws == null || _closedByClient) return false;
      final state = _ws!.getProperty<JSNumber?>('readyState'.toJS)?.toDartInt;
      return state == 1; // OPEN
    } catch (_) {
      return false;
    }
  }

  void send(String message) {
    try {
      if (isOpen) {
        _ws?.callMethod<JSAny?>('send'.toJS, message.toJS);
      }
    } catch (_) {}
  }

  void close() {
    _closedByClient = true;
    try {
      _ws?.callMethod<JSAny?>('close'.toJS);
    } catch (_) {}
    _ws = null;
  }
}

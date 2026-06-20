import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

const _defaultRoot = r'E:\music';
const _defaultHost = '0.0.0.0';
const _defaultPort = 8787;
const _supportedExtensions = {'mp3', 'flac'};

Future<void> main(List<String> args) async {
  final options = _ServerOptions.fromArgs(args);
  final root = Directory(options.root);
  if (!await root.exists()) {
    stderr.writeln('Music root does not exist: ${root.path}');
    exitCode = 64;
    return;
  }

  final resolvedRoot = await root.resolveSymbolicLinks();
  final server = await HttpServer.bind(options.host, options.port);
  stdout.writeln(
    'AI Music source server listening on http://${options.host}:${options.port}',
  );
  stdout.writeln('Music root: $resolvedRoot');

  await for (final request in server) {
    try {
      await _handleRequest(request, resolvedRoot);
    } catch (error, stackTrace) {
      stderr.writeln(error);
      stderr.writeln(stackTrace);
      try {
        request.response.statusCode = HttpStatus.internalServerError;
      } catch (_) {
        // The response may already be streaming media bytes.
      }
      await request.response.close();
    }
  }
}

Future<void> _handleRequest(HttpRequest request, String rootPath) async {
  final path = request.uri.toString().split('?').first;
  if (request.method != 'GET' && request.method != 'HEAD') {
    await _sendJson(request, HttpStatus.methodNotAllowed, {
      'error': 'method_not_allowed',
    });
    return;
  }

  if (path == '/api/health') {
    final tracks = await _scanTracks(rootPath, _requestOrigin(request));
    await _sendJson(request, HttpStatus.ok, {
      'status': 'ok',
      'root': rootPath,
      'trackCount': tracks.length,
      'extensions': {
        for (final extension in _supportedExtensions)
          extension: tracks
              .where((track) => track.extension == extension)
              .length,
      },
    });
    return;
  }

  if (path == '/api/tracks') {
    final tracks = await _scanTracks(rootPath, _requestOrigin(request));
    await _sendJson(request, HttpStatus.ok, {
      'version': 1,
      'tracks': tracks.map((track) => track.toJson()).toList(),
    });
    return;
  }

  if (path.startsWith('/media/')) {
    await _sendMedia(request, rootPath, path.substring('/media/'.length));
    return;
  }

  await _sendJson(request, HttpStatus.notFound, {'error': 'not_found'});
}

Future<List<_TrackManifestItem>> _scanTracks(
  String rootPath,
  String origin,
) async {
  final root = Directory(rootPath);
  final files = <File>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) {
      continue;
    }
    final extension = _extensionOf(entity.path);
    if (_supportedExtensions.contains(extension)) {
      files.add(entity);
    }
  }

  files.sort((left, right) => left.path.compareTo(right.path));
  return [
    for (final file in files)
      _TrackManifestItem.fromFile(
        file: file,
        relativePath: _relativePath(rootPath, file.path),
        origin: origin,
      ),
  ];
}

Future<void> _sendMedia(
  HttpRequest request,
  String rootPath,
  String encodedRelativePath,
) async {
  final relativeSegments = encodedRelativePath
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .map(Uri.decodeComponent)
      .toList(growable: false);
  if (relativeSegments.isEmpty || relativeSegments.any(_isUnsafeSegment)) {
    await _sendJson(request, HttpStatus.badRequest, {
      'error': 'bad_media_path',
    });
    return;
  }

  final file = File(_join(rootPath, relativeSegments));
  if (!await file.exists()) {
    await _sendJson(request, HttpStatus.notFound, {'error': 'media_not_found'});
    return;
  }

  final resolvedRoot = await Directory(rootPath).resolveSymbolicLinks();
  final resolvedFile = await file.resolveSymbolicLinks();
  if (!_isWithinRoot(resolvedRoot, resolvedFile)) {
    await _sendJson(request, HttpStatus.forbidden, {'error': 'forbidden'});
    return;
  }

  final length = await file.length();
  final extension = _extensionOf(file.path);
  final range = _parseRange(
    request.headers.value(HttpHeaders.rangeHeader),
    length,
  );

  request.response.headers
    ..set(HttpHeaders.acceptRangesHeader, 'bytes')
    ..contentType = _contentTypeFor(extension);

  if (range == null) {
    request.response.statusCode = HttpStatus.ok;
    request.response.contentLength = length;
    if (request.method == 'HEAD') {
      await request.response.close();
      return;
    }
    await file.openRead().pipe(request.response);
    return;
  }

  if (!range.isValid) {
    request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
    request.response.headers.set(
      HttpHeaders.contentRangeHeader,
      'bytes */$length',
    );
    await request.response.close();
    return;
  }

  request.response.statusCode = HttpStatus.partialContent;
  request.response.contentLength = range.length;
  request.response.headers.set(
    HttpHeaders.contentRangeHeader,
    'bytes ${range.start}-${range.end}/$length',
  );
  if (request.method == 'HEAD') {
    await request.response.close();
    return;
  }
  await file.openRead(range.start, range.end + 1).pipe(request.response);
}

Future<void> _sendJson(
  HttpRequest request,
  int statusCode,
  Map<String, Object?> body,
) async {
  final payload = utf8.encode(const JsonEncoder.withIndent('  ').convert(body));
  request.response
    ..statusCode = statusCode
    ..headers.contentType = ContentType.json
    ..contentLength = payload.length;
  if (request.method != 'HEAD') {
    request.response.add(payload);
  }
  await request.response.close();
}

String _requestOrigin(HttpRequest request) {
  final host = request.headers.value(HttpHeaders.hostHeader);
  if (host != null && host.isNotEmpty) {
    return 'http://$host';
  }
  final port = request.connectionInfo?.localPort ?? _defaultPort;
  return 'http://127.0.0.1:$port';
}

String _relativePath(String rootPath, String filePath) {
  final normalizedRoot = _trimTrailingSeparator(rootPath);
  final normalizedFile = filePath;
  if (normalizedFile.length <= normalizedRoot.length) {
    return _fileName(filePath);
  }
  return normalizedFile.substring(normalizedRoot.length + 1);
}

String _join(String rootPath, List<String> segments) {
  final buffer = StringBuffer(_trimTrailingSeparator(rootPath));
  for (final segment in segments) {
    buffer
      ..write(Platform.pathSeparator)
      ..write(segment);
  }
  return buffer.toString();
}

String _trimTrailingSeparator(String path) {
  while (path.length > 1 &&
      (path.endsWith(r'\') || path.endsWith('/')) &&
      !RegExp(r'^[A-Za-z]:[\\/]$').hasMatch(path)) {
    path = path.substring(0, path.length - 1);
  }
  return path;
}

bool _isWithinRoot(String rootPath, String filePath) {
  final normalizedRoot = _trimTrailingSeparator(rootPath).toLowerCase();
  final normalizedFile = filePath.toLowerCase();
  return normalizedFile == normalizedRoot ||
      normalizedFile.startsWith('$normalizedRoot${Platform.pathSeparator}');
}

bool _isUnsafeSegment(String segment) {
  return segment == '.' ||
      segment == '..' ||
      segment.contains(Platform.pathSeparator) ||
      segment.contains('/') ||
      segment.contains(r'\');
}

_ByteRange? _parseRange(String? value, int totalLength) {
  if (value == null || value.isEmpty) {
    return null;
  }
  final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(value.trim());
  if (match == null) {
    return const _ByteRange.invalid();
  }

  final startText = match.group(1)!;
  final endText = match.group(2)!;
  if (startText.isEmpty && endText.isEmpty) {
    return const _ByteRange.invalid();
  }

  if (startText.isEmpty) {
    final suffixLength = int.tryParse(endText);
    if (suffixLength == null || suffixLength <= 0) {
      return const _ByteRange.invalid();
    }
    final start = math.max(0, totalLength - suffixLength);
    return _ByteRange(start, totalLength - 1);
  }

  final start = int.tryParse(startText);
  final end = endText.isEmpty ? totalLength - 1 : int.tryParse(endText);
  if (start == null || end == null) {
    return const _ByteRange.invalid();
  }
  if (start < 0 || end < start || start >= totalLength) {
    return const _ByteRange.invalid();
  }
  return _ByteRange(start, math.min(end, totalLength - 1));
}

ContentType _contentTypeFor(String extension) {
  return switch (extension) {
    'mp3' => ContentType('audio', 'mpeg'),
    'flac' => ContentType('audio', 'flac'),
    _ => ContentType.binary,
  };
}

String _extensionOf(String path) {
  final name = _fileName(path);
  final index = name.lastIndexOf('.');
  if (index < 0 || index == name.length - 1) {
    return '';
  }
  return name.substring(index + 1).toLowerCase();
}

String _fileName(String path) {
  final normalized = path.replaceAll(r'\', '/');
  final index = normalized.lastIndexOf('/');
  return index < 0 ? normalized : normalized.substring(index + 1);
}

String _withoutExtension(String fileName) {
  final index = fileName.lastIndexOf('.');
  return index < 0 ? fileName : fileName.substring(0, index);
}

String _encodedRelativeUrlPath(String relativePath) {
  return relativePath
      .replaceAll(r'\', '/')
      .split('/')
      .map(Uri.encodeComponent)
      .join('/');
}

class _ServerOptions {
  const _ServerOptions({
    required this.root,
    required this.host,
    required this.port,
  });

  final String root;
  final String host;
  final int port;

  factory _ServerOptions.fromArgs(List<String> args) {
    var root = _defaultRoot;
    var host = _defaultHost;
    var port = _defaultPort;

    for (var index = 0; index < args.length; index++) {
      final arg = args[index];
      String nextValue() {
        if (index + 1 >= args.length) {
          throw ArgumentError('Missing value for $arg');
        }
        index++;
        return args[index];
      }

      switch (arg) {
        case '--root':
          root = nextValue();
        case '--host':
          host = nextValue();
        case '--port':
          port = int.parse(nextValue());
        case '--help':
        case '-h':
          stdout.writeln(
            'Usage: dart run tool/music_source_server.dart '
            '[--root E:\\music] [--host 0.0.0.0] [--port 8787]',
          );
          exit(0);
        default:
          throw ArgumentError('Unknown argument: $arg');
      }
    }

    return _ServerOptions(root: root, host: host, port: port);
  }
}

class _TrackManifestItem {
  const _TrackManifestItem({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.fileName,
    required this.extension,
    required this.size,
    required this.sourceUrl,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final String fileName;
  final String extension;
  final int size;
  final String sourceUrl;

  factory _TrackManifestItem.fromFile({
    required File file,
    required String relativePath,
    required String origin,
  }) {
    final fileName = _fileName(file.path);
    final stem = _withoutExtension(fileName).trim();
    final dashIndex = stem.indexOf('-');
    final artist = dashIndex <= 0
        ? 'Unknown'
        : stem.substring(0, dashIndex).trim();
    final title = dashIndex < 0 || dashIndex == stem.length - 1
        ? stem
        : stem.substring(dashIndex + 1).trim();
    final encodedPath = _encodedRelativeUrlPath(relativePath);

    return _TrackManifestItem(
      id: base64Url.encode(utf8.encode(relativePath)).replaceAll('=', ''),
      title: title.isEmpty ? stem : title,
      artist: artist.isEmpty ? 'Unknown' : artist,
      album: 'Local Music',
      fileName: fileName,
      extension: _extensionOf(file.path),
      size: file.lengthSync(),
      sourceUrl: '$origin/media/$encodedPath',
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'fileName': fileName,
      'extension': extension,
      'size': size,
      'sourceUrl': sourceUrl,
    };
  }
}

class _ByteRange {
  const _ByteRange(this.start, this.end) : isValid = true;
  const _ByteRange.invalid() : start = -1, end = -1, isValid = false;

  final int start;
  final int end;
  final bool isValid;

  int get length => end - start + 1;
}

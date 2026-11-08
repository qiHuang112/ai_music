import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'resolver_models.dart';
import 'provider_request_scheduler.dart';
import 'operation_log.dart';

class HttpMusicResolverClient implements MusicResolverHttp {
  HttpMusicResolverClient({this.client, ProviderRequestScheduler? scheduler})
    : _scheduler = scheduler ?? ProviderRequestScheduler.shared;

  final HttpClient? client;
  final ProviderRequestScheduler _scheduler;
  HttpClient? _ownedClient;

  void close() => _ownedClient?.close(force: true);
  void resetSourceNetworkState() => _scheduler.resetForNetworkChange();

  @override
  Future<ResolverHttpResponse> get(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    return _send('GET', uri, headers: headers);
  }

  @override
  Future<ResolverHttpResponse> postForm(
    Uri uri,
    Map<String, String> form, {
    Map<String, String> headers = const {},
  }) async {
    return _send(
      'POST',
      uri,
      headers: {
        'content-type': 'application/x-www-form-urlencoded;charset=UTF-8',
        ...headers,
      },
      body: utf8.encode(Uri(queryParameters: form).query),
    );
  }

  @override
  Future<ResolverHttpResponse> postJson(
    Uri uri,
    Object body, {
    Map<String, String> headers = const {},
  }) async {
    return _send(
      'POST',
      uri,
      headers: {'content-type': 'application/json', ...headers},
      body: utf8.encode(jsonEncode(body)),
    );
  }

  Future<ResolverHttpResponse> _send(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    Object? lastError;
    final watch = Stopwatch()..start();
    OperationLog.event('http.start', {
      'method': method,
      'host': uri.host,
      'path': uri.path,
    });
    // BuguYY owns its three-attempt retry loop. Nesting another loop here
    // previously multiplied a single failure into nine transport attempts.
    final attempts = uri.host == 'buguyy.top' ? 1 : 2;
    for (var attempt = 0; attempt < attempts; attempt += 1) {
      try {
        final response = await _scheduler.run(
          uri,
          () => _sendOnce(method, uri, headers: headers, body: body),
        );
        OperationLog.event('http.complete', {
          'method': method,
          'host': uri.host,
          'path': uri.path,
          'status': response.statusCode,
          'elapsedMs': watch.elapsedMilliseconds,
        });
        return response;
      } catch (error) {
        OperationLog.event('http.failed', {
          'method': method,
          'host': uri.host,
          'path': uri.path,
          'attempt': attempt + 1,
          'error': error.toString(),
          'elapsedMs': watch.elapsedMilliseconds,
        });
        lastError = error;
        if (!_isTransientNetworkError(error) || attempt == attempts - 1) {
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
      }
    }
    throw StateError('HTTP request failed: $lastError');
  }

  Future<ResolverHttpResponse> _sendOnce(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    final httpClient = client ?? (_ownedClient ??= HttpClient());
    final request = await httpClient
        .openUrl(method, uri)
        .timeout(const Duration(seconds: 12));
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    if (body != null) {
      request.contentLength = body.length;
      request.add(body);
    }

    final response = await request.close().timeout(const Duration(seconds: 20));
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(seconds: 20))) {
      bytes.add(chunk);
      // Resolver responses are JSON or HTML pages; anything this large is
      // not one, and must not grow memory without bound.
      if (bytes.length > maxResponseBytes) {
        throw HttpException('Response larger than $maxResponseBytes bytes', uri: uri);
      }
    }
    // Lenient: one bad byte from a source must not fail the whole request.
    final responseBody = utf8.decode(bytes.takeBytes(), allowMalformed: true);
    final headerMap = <String, String>{};
    response.headers.forEach((name, values) {
      if (values.isNotEmpty) {
        headerMap[name] = values.join(', ');
      }
    });
    return ResolverHttpResponse(
      statusCode: response.statusCode,
      body: responseBody,
      finalUrl: resolveRedirects(uri, [
        for (final r in response.redirects) r.location,
      ]),
      cookies: lenientCookies(response),
      headers: headerMap,
    );
  }
}

bool _isTransientNetworkError(Object error) {
  return error is TimeoutException ||
      error is SocketException ||
      error is HandshakeException ||
      error is HttpException;
}


/// Upper bound for one resolver response body.
const maxResponseBytes = 8 * 1024 * 1024;

/// The URL a chain of redirects ends at. A `Location` may be relative to the
/// URL it came from.
Uri resolveRedirects(Uri start, List<Uri> locations) {
  var current = start;
  for (final location in locations) {
    current = current.resolveUri(location);
  }
  return current;
}

/// The response's cookies, skipping any `Set-Cookie` value Dart's strict
/// parser rejects (spaces, quotes, non-ASCII) instead of failing the request.
List<Cookie> lenientCookies(HttpClientResponse response) {
  try {
    return response.cookies;
  } on Exception {
    // FormatException or HttpException from a bad Set-Cookie value.
    return parseSetCookies(response.headers[HttpHeaders.setCookieHeader] ?? const []);
  }
}

List<Cookie> parseSetCookies(List<String> values) => [
  for (final value in values) ?_tryCookie(value),
];

Cookie? _tryCookie(String value) {
  try {
    return Cookie.fromSetCookieValue(value);
  } on Object {
    return null;
  }
}

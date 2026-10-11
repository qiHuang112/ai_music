import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
    final responseBody = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 20));
    final headerMap = <String, String>{};
    response.headers.forEach((name, values) {
      if (values.isNotEmpty) {
        headerMap[name] = values.join(', ');
      }
    });
    return ResolverHttpResponse(
      statusCode: response.statusCode,
      body: responseBody,
      finalUrl: response.redirects.isNotEmpty
          ? response.redirects.last.location
          : uri,
      cookies: response.cookies,
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

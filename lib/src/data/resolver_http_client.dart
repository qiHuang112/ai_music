import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'resolver_models.dart';

class HttpMusicResolverClient implements MusicResolverHttp {
  HttpMusicResolverClient({this.client});

  final HttpClient? client;

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
    for (var attempt = 0; attempt < 3; attempt += 1) {
      try {
        return await _sendOnce(method, uri, headers: headers, body: body);
      } catch (error) {
        lastError = error;
        if (!_isTransientNetworkError(error) || attempt == 2) {
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
    final ownsClient = client == null;
    final httpClient = client ?? HttpClient();
    try {
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

      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final responseBody = await response.transform(utf8.decoder).join();
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
    } finally {
      if (ownsClient) {
        httpClient.close(force: true);
      }
    }
  }
}

bool _isTransientNetworkError(Object error) {
  return error is TimeoutException ||
      error is SocketException ||
      error is HandshakeException ||
      error is HttpException;
}

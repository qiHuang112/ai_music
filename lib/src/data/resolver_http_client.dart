import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'resolver_models.dart';

class HttpMusicResolverClient implements MusicResolverHttp {
  HttpMusicResolverClient({
    this.client,
    this.connectTimeout = const Duration(seconds: 5),
    this.responseTimeout = const Duration(seconds: 8),
    this.retryAttempts = 1,
  }) : assert(retryAttempts > 0);

  final HttpClient? client;
  final Duration connectTimeout;
  final Duration responseTimeout;
  final int retryAttempts;

  @override
  Future<ResolverHttpResponse> get(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    return _send('GET', uri, headers: headers);
  }

  @override
  Future<ResolverHttpResponse> head(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    return _send('HEAD', uri, headers: headers, retry: false);
  }

  @override
  Future<ResolverHttpResponse> range(
    Uri uri, {
    int start = 0,
    int end = 0,
    Map<String, String> headers = const {},
  }) async {
    return _send(
      'GET',
      uri,
      headers: {'range': 'bytes=$start-$end', ...headers},
      retry: false,
      maxBodyBytes: 1024,
    );
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
    bool retry = true,
    int? maxBodyBytes,
  }) async {
    Object? lastError;
    final attempts = retry ? retryAttempts : 1;
    for (var attempt = 0; attempt < attempts; attempt += 1) {
      try {
        return await _sendOnce(
          method,
          uri,
          headers: headers,
          body: body,
          maxBodyBytes: maxBodyBytes,
        );
      } catch (error) {
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
    int? maxBodyBytes,
  }) async {
    final ownsClient = client == null;
    final httpClient = client ?? HttpClient();
    try {
      final request = await httpClient
          .openUrl(method, uri)
          .timeout(connectTimeout);
      for (final entry in headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      if (body != null) {
        request.contentLength = body.length;
        request.add(body);
      }

      final response = await request.close().timeout(responseTimeout);
      final responseBody = await _readBody(
        response,
        maxBodyBytes,
      ).timeout(responseTimeout);
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

Future<String> _readBody(HttpClientResponse response, int? maxBodyBytes) async {
  if (maxBodyBytes == null) {
    return response.transform(utf8.decoder).join();
  }
  final chunks = <int>[];
  await for (final chunk in response) {
    final available = maxBodyBytes - chunks.length;
    if (available <= 0) {
      break;
    }
    chunks.addAll(chunk.take(available));
    if (chunks.length >= maxBodyBytes) {
      break;
    }
  }
  return utf8.decode(chunks, allowMalformed: true);
}

bool _isTransientNetworkError(Object error) {
  return error is TimeoutException ||
      error is SocketException ||
      error is HandshakeException ||
      error is HttpException;
}

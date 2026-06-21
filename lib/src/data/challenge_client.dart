import 'dart:convert';
import 'dart:math';

import 'resolver_models.dart';
import 'resolver_utils.dart';

class ChallengeClient {
  ChallengeClient({
    required MusicResolverHttp httpClient,
    String initialCookie = '',
    this.apiBaseUrl = 'https://flac.music.hi.cn',
    this.challengeBaseUrl = 'https://challenge.rivers.chaitin.cn',
  }) : _http = httpClient,
       _flacCookie = initialCookie;

  static const userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  final MusicResolverHttp _http;
  final String apiBaseUrl;
  final String challengeBaseUrl;
  String _flacCookie;

  Future<Map<String, dynamic>> postFlacApi(
    String act,
    Map<String, String> form,
  ) async {
    final cookie = await ensureCookie();
    try {
      return await _postFlacApi(cookie, act, form);
    } catch (error) {
      if (!looksLikeChallengeError(error)) {
        rethrow;
      }
      final refreshed = await refreshCookie();
      return _postFlacApi(refreshed, act, form);
    }
  }

  Future<String> ensureCookie() async {
    if (_flacCookie.isNotEmpty) {
      return _flacCookie;
    }
    _flacCookie = await refreshCookie();
    return _flacCookie;
  }

  Future<String> refreshCookie() async {
    final fresh = await _generateFlacCookie();
    _flacCookie = fresh.cookie;
    return _flacCookie;
  }

  Future<_CookieResult> _generateFlacCookie() async {
    final first = await _fetchHomeThroughDefenders();
    final slSession = _getCookieValue(first.setCookies, 'sl-session');
    final clientId =
        RegExp(
          r'SafeLineChallenge\("([^"]+)"',
        ).firstMatch(first.body)?.group(1) ??
        '';

    if (slSession.isEmpty || clientId.isEmpty) {
      return _CookieResult(
        cookie: first.cookie,
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      );
    }

    final issue = await _postChallengeJson('/challenge/v2/api/issue', {
      'client_id': clientId,
      'level': 1,
    });
    final issueData = asStringMap(issue['data']);
    final input = (issueData['data'] is List ? issueData['data'] as List : [])
        .whereType<num>()
        .map((value) => value.toInt())
        .toList(growable: false);
    final result = _calculateChallengeResult(input);

    final verify = await _postChallengeJson('/challenge/v2/api/verify', {
      'issue_id': issueData['issue_id'],
      'result': result,
      'serials': const [],
      'client': const {
        'userAgent': userAgent,
        'platform': 'Win32',
        'language': 'zh-CN',
        'vendor': 'Google Inc.',
        'screen': [1920, 1080],
        'visitorId': '99999999999999999999999999999999',
        'score': 0,
        'target': [],
      },
    });

    final jwt = asStringMap(verify['data'])['jwt']?.toString() ?? '';
    if (jwt.isEmpty) {
      throw StateError('SafeLine verify failed: ${jsonEncode(verify)}');
    }

    final finalPage = await _fetchHomeThroughDefenders(
      cookie:
          'sl-session=$slSession; sl-challenge-server=cloud; '
          'sl-challenge-jwt=$jwt',
    );
    final cookieParts = [
      'sl-session=$slSession',
      'sl-challenge-server=cloud',
      'sl_jwt_session=${_getCookieValue(finalPage.setCookies, 'sl_jwt_session')}',
      'sl_jwt_sign=${_getCookieValue(finalPage.setCookies, 'sl_jwt_sign')}',
      'sl-challenge-jwt=$jwt',
    ];
    return _CookieResult(
      cookie: cookieParts.join('; '),
      expiresAt: DateTime.now().add(const Duration(minutes: 55)),
    );
  }

  Future<Map<String, dynamic>> _postChallengeJson(
    String path,
    Object body,
  ) async {
    final response = await _http.postJson(
      Uri.parse('$challengeBaseUrl$path'),
      body,
      headers: {
        'origin': apiBaseUrl,
        'referer': '$apiBaseUrl/',
        'user-agent': userAgent,
      },
    );
    return _decodeJson(response, label: 'SafeLine');
  }

  Future<_DefenderPage> _fetchHomeThroughDefenders({
    String cookie = '',
    String startPath = '/',
  }) async {
    var url = startPath.startsWith('http')
        ? startPath
        : '$apiBaseUrl$startPath';
    var latestCookie = cookie;
    var latestBody = '';
    var latestSetCookies = <String>[];

    for (var attempt = 0; attempt < 4; attempt += 1) {
      final response = await _http.get(
        Uri.parse(url),
        headers: {
          'accept-language': 'zh-CN,zh;q=0.9',
          if (latestCookie.isNotEmpty) 'cookie': latestCookie,
          'referer': '$apiBaseUrl/',
          'user-agent': userAgent,
        },
      );
      latestBody = response.body;
      latestSetCookies = response.cookies
          .map((cookie) => '${cookie.name}=${cookie.value}')
          .where((cookie) => cookie.trim().isNotEmpty)
          .toList(growable: false);
      if (latestSetCookies.isNotEmpty) {
        latestCookie = [
          if (latestCookie.isNotEmpty) latestCookie,
          ...latestSetCookies,
        ].join('; ');
      }

      final redirect = parseAntiCcRedirect(latestBody);
      if (redirect.isEmpty) {
        break;
      }
      url = '$apiBaseUrl$redirect';
    }

    return _DefenderPage(
      body: latestBody,
      cookie: latestCookie,
      setCookies: latestSetCookies,
    );
  }

  Future<Map<String, dynamic>> _postFlacApi(
    String cookie,
    String act,
    Map<String, String> form,
  ) async {
    var currentCookie = cookie;
    var lastText = '';

    for (var attempt = 0; attempt < 3; attempt += 1) {
      final response = await _http.postForm(
        Uri.parse('$apiBaseUrl/ajax.php?act=$act'),
        form,
        headers: {
          'accept': 'application/json, text/javascript, */*; q=0.01',
          if (currentCookie.isNotEmpty) 'cookie': currentCookie,
          'origin': apiBaseUrl,
          'referer': '$apiBaseUrl/',
          'user-agent': userAgent,
          'x-requested-with': 'XMLHttpRequest',
        },
      );
      lastText = response.body;
      try {
        final json = _decodeJson(response, label: act);
        if (!response.ok) {
          throw StateError('$act HTTP ${response.statusCode}');
        }
        _flacCookie = currentCookie;
        return json;
      } catch (_) {
        final redirect = parseAntiCcRedirect(response.body);
        if (redirect.isEmpty) {
          rethrow;
        }
        final defended = await _fetchHomeThroughDefenders(
          cookie: currentCookie,
          startPath: redirect,
        );
        if (defended.cookie.isNotEmpty) {
          currentCookie = defended.cookie;
        }
      }
    }

    throw FormatException('Non-JSON response from $act: ${prefix(lastText)}');
  }

  Map<String, dynamic> _decodeJson(
    ResolverHttpResponse response, {
    required String label,
  }) {
    try {
      return asStringMap(jsonDecode(response.body));
    } catch (_) {
      throw FormatException(
        '$label non-JSON response ${response.statusCode}: '
        '${prefix(response.body)}',
      );
    }
  }
}

bool looksLikeChallengeError(Object error) {
  final text = formatResolverError(error);
  return RegExp(
    r'challenge|SafeLine|Non-JSON',
    caseSensitive: false,
  ).hasMatch(text);
}

String parseAntiCcRedirect(String html) {
  if (!html.contains('cbk_var') || !html.contains('window.location')) {
    return '';
  }
  var value = '';
  final source = html.split(RegExp(r';\s*cbk_defender_')).first;
  final pattern = RegExp(
    r"cbk_var\s*=\s*(?:'([^']*)'\s*\+\s*cbk_var|cbk_var\s*\+\s*'([^']*)'|'([^']*)')",
  );
  for (final match in pattern.allMatches(source)) {
    if (match.group(1) != null) {
      value = '${match.group(1)}$value';
    } else if (match.group(2) != null) {
      value += match.group(2)!;
    } else {
      value = match.group(3) ?? '';
    }
  }
  return value.startsWith('/') ? value : '';
}

List<int> _calculateChallengeResult(List<int> input) {
  var value = 1;
  final sum = input.fold<int>(0, (acc, value) => acc + value);
  var cycles = ((6 + input.length + sum) % 6) + 6;

  while (cycles > 0) {
    value *= 6;
    cycles -= 1;
  }
  if (value < 6666) {
    value *= input.length;
  }
  if (value > 0x3f940aa && input.isNotEmpty) {
    value = value ~/ input.length;
  }

  for (var index = 0; index < input.length; index += 1) {
    value += pow(input[index], 3).toInt();
    value ^= index;
    value ^= input[index] + index;
  }

  final result = <int>[];
  while (value > 0) {
    result.insert(0, value & 63);
    value >>= 6;
  }
  return result;
}

String _getCookieValue(List<String> cookies, String name) {
  final escaped = RegExp.escape(name);
  final pattern = RegExp('$escaped=([^;]+)');
  for (final cookie in cookies) {
    final match = pattern.firstMatch(cookie);
    if (match != null) {
      return match.group(1) ?? '';
    }
  }
  return '';
}

class _CookieResult {
  const _CookieResult({required this.cookie, required this.expiresAt});

  final String cookie;
  final DateTime expiresAt;
}

class _DefenderPage {
  const _DefenderPage({
    required this.body,
    required this.cookie,
    required this.setCookies,
  });

  final String body;
  final String cookie;
  final List<String> setCookies;
}

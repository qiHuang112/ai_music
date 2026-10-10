import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:ai_music/src/application/app_update_controller.dart';
import 'package:crypto/crypto.dart';
import 'package:ai_music/src/presentation/app_update_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late Directory root;
  late HttpServer server;
  late AppUpdateController updates;
  late _Bridge bridge;
  late Map<String, dynamic> manifest;
  final bytes = List<int>.generate(8192, (i) => i % 256);
  var corrupted = false;
  var slow = false;
  var requests = 0;
  var apkRequests = 0;
  var metadataStatus = 200;
  Completer<void>? metadataGate;
  Completer<void>? metadataStarted;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('app_update_');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    bridge = _Bridge();
    corrupted = false;
    slow = false;
    requests = 0;
    apkRequests = 0;
    metadataStatus = 200;
    metadataGate = null;
    metadataStarted = null;
    manifest = {
      'packageName': 'com.qi.ai.music',
      'channel': 'release',
      'abi': 'arm64-v8a',
      'versionName': '1.0.2',
      'versionCode': 101,
      'publishedAt': '2026-10-04T01:00:00Z',
      'url': '/releases/app.apk',
      'sizeBytes': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
      'notes': 'Test release',
    };
    server.listen((request) async {
      try {
        if (request.uri.path == '/api/v1/update/android') {
          requests++;
          metadataStarted?.complete();
          if (metadataGate != null) await metadataGate!.future;
          request.response.statusCode = metadataStatus;
          if (metadataStatus != 204) {
            request.response.write(jsonEncode(manifest));
          }
        } else {
          apkRequests++;
          request.response.add(corrupted ? bytes.sublist(1) : bytes);
          if (slow) {
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
        }
        await request.response.close();
      } catch (_) {}
    });
    updates = AppUpdateController(
      bridge: bridge,
      supported: true,
      cacheRoot: () async => root,
      configFile: () async => File('${root.path}/update.json'),
    );
    await updates.initialize();
    await updates.saveServer('http://127.0.0.1:${server.port}');
  });
  tearDown(() async {
    updates.dispose();
    await server.close(force: true);
    await root.delete(recursive: true);
  });
  test(
    'compares actual build codes, throttles checks and installs only verified bytes',
    () async {
      expect(updates.current!.label, '1.0.1 (100)');
      expect(updates.hasUpdate, isTrue);
      await updates.check();
      expect(requests, 1);
      await updates.downloadAndInstall();
      expect(bridge.installs, 1);
      expect(await bridge.file!.readAsBytes(), bytes);
      expect(updates.received, bytes.length);
      expect(
        updates.hasUpdate,
        isTrue,
      ); // Red dot persists until the app is actually replaced.
    },
  );
  test('equal and lower versions are not updates', () async {
    manifest['versionCode'] = 100;
    await updates.check(force: true);
    expect(updates.hasUpdate, isFalse);
    manifest['versionCode'] = 99;
    await updates.check(force: true);
    await updates.downloadAndInstall();
    expect(bridge.installs, 0);
  });
  test(
    'truncated or corrupted APK never reaches installer and partial file is removed',
    () async {
      corrupted = true;
      await updates.downloadAndInstall();
      expect(bridge.installs, 0);
      expect(updates.downloadedApk, isNull);
      expect(updates.error, contains('校验失败'));
      expect(
        await Directory('${root.path}/ai_music_updates').list().toList(),
        isEmpty,
      );
      corrupted = false;
      await updates.downloadAndInstall();
      expect(bridge.installs, 1);
    },
  );
  test('cancel closes download and does not open installer', () async {
    slow = true;
    final started = Completer<void>();
    updates.addListener(() {
      if (updates.received > 0 && !started.isCompleted) started.complete();
    });
    final task = updates.downloadAndInstall();
    await started.future;
    updates.cancelDownload();
    await task;
    expect(updates.downloading, isFalse);
    expect(updates.downloadedApk, isNull);
    expect(bridge.installs, 0);
  });
  test(
    'incompatible package, ABI and external download URLs are rejected',
    () async {
      for (final entry in {
        'packageName': 'other.app',
        'abi': 'x86_64',
        'url': 'http://other.invalid/app.apk',
        'channel': 'debug',
      }.entries) {
        final original = manifest[entry.key];
        manifest[entry.key] = entry.value;
        expect(
          () => AppRelease.parse(
            manifest,
            Uri.parse('http://127.0.0.1:${server.port}'),
            updates.current!,
          ),
          throwsFormatException,
        );
        manifest[entry.key] = original;
      }
    },
  );
  test(
    'install permission can be granted then installation retried without downloading again',
    () async {
      bridge.allowed = false;
      await updates.downloadAndInstall();
      final apk = updates.downloadedApk;
      expect(updates.installNotice, contains('请允许'));
      bridge.allowed = true;
      await updates.downloadAndInstall();
      expect(updates.downloadedApk, same(apk));
      expect(bridge.installs, 2);
    },
  );
  test('debug does not request release updates', () async {
    final debug = AppUpdateController(
      supported: true,
      bridge: _Bridge(channel: 'debug'),
      cacheRoot: () async => root,
      configFile: () async => File('${root.path}/update.json'),
    );
    await debug.check(force: true);
    expect(debug.current!.channel, 'debug');
    expect(debug.hasUpdate, isFalse);
    expect(requests, 1);
    debug.dispose();
  });
  test(
    'pending recheck blocks previously downloaded update until success',
    () async {
      bridge.allowed = false;
      await updates.downloadAndInstall();
      final apk = updates.downloadedApk;
      metadataGate = Completer<void>();
      metadataStarted = Completer<void>();
      final check = updates.check(force: true);
      await metadataStarted!.future;
      expect(updates.checking, isTrue);
      expect(updates.hasUpdate, isFalse);
      await updates.downloadAndInstall();
      await updates.installDownloaded();
      expect(bridge.installs, 1);
      metadataGate!.complete();
      await check;
      expect(updates.hasUpdate, isTrue);
      expect(updates.downloadedApk, same(apk));
      await updates.installDownloaded();
      expect(bridge.installs, 2);
    },
  );

  test('withdrawn release clears downloaded installer reference', () async {
    bridge.allowed = false;
    await updates.downloadAndInstall();
    metadataStatus = 204;
    await updates.check(force: true);
    expect(updates.latest, isNull);
    expect(updates.downloadedApk, isNull);
    expect(updates.hasUpdate, isFalse);
    expect(updates.checked, isTrue);
    expect(updates.error, isNull);
    await updates.downloadAndInstall();
    await updates.installDownloaded();
    expect(bridge.installs, 1);
  });

  for (final failure in ['unavailable', 'invalid metadata']) {
    testWidgets(
      'failed recheck ($failure) hides stale update and blocks install',
      (tester) async {
        bridge.allowed = false;
        await tester.runAsync(updates.downloadAndInstall);
        expect(updates.downloadedApk, isNotNull);
        expect(bridge.installs, 1);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  UpdateBadge(
                    updates: updates,
                    child: const Icon(Icons.settings),
                  ),
                  Expanded(child: AppUpdatePage(updates: updates)),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('install-app-update')), findsOneWidget);
        expect(
          tester
              .widget<Badge>(find.byKey(const Key('app-update-badge')))
              .isLabelVisible,
          isTrue,
        );
        await tester.runAsync(() async {
          if (failure == 'unavailable') {
            await server.close(force: true);
          } else {
            manifest['packageName'] = 'invalid.app';
          }
          await updates.check(force: true);
        });
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('update-error')), findsOneWidget);
        expect(find.byKey(const Key('install-app-update')), findsNothing);
        expect(
          tester
              .widget<Badge>(find.byKey(const Key('app-update-badge')))
              .isLabelVisible,
          isFalse,
        );
        expect(updates.latest, isNull);
        expect(updates.downloadedApk, isNull);
        expect(updates.hasUpdate, isFalse);
        final previousRequests = apkRequests;
        await tester.runAsync(() async {
          await updates.downloadAndInstall();
          await updates.installDownloaded();
        });
        expect(bridge.installs, 1);
        expect(apkRequests, previousRequests);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  test('unavailable server is reported rather than up-to-date', () async {
    await server.close(force: true);
    await updates.check(force: true);
    expect(updates.error, contains('无法连接'));
  });

  test('default update uses LAN immediately without a GitHub probe', () async {
    final client = _UpdateClient([
      _Reply(200, bytes: utf8.encode(jsonEncode(manifest))),
      _Reply(200, bytes: bytes),
    ]);
    final local = AppUpdateController(
      bridge: bridge,
      supported: true,
      cacheRoot: () async => root,
      configFile: () async => File('${root.path}/default.json'),
      clientFactory: () => client,
    );
    addTearDown(local.dispose);
    await local.check(force: true);
    expect(local.hasUpdate, isTrue);
    expect(local.error, isNull);
    expect(
      client.uris.single.toString(),
      '$defaultUpdateUrl/api/v1/update/android',
    );
    await local.downloadAndInstall();
    expect(client.uris.last.toString(), '$defaultUpdateUrl/releases/app.apk');
    expect(bridge.installs, 1);
  });

  test('LAN timeout falls back silently within the bounded probe', () async {
    final client = _HangingLanClient([
      _Reply(
        200,
        bytes: utf8.encode(
          jsonEncode({
            ...manifest,
            'url': '$githubUpdateUrl/releases/download/v1/app.apk',
          }),
        ),
      ),
    ]);
    final local = AppUpdateController(
      bridge: bridge,
      supported: true,
      configFile: () async => File('${root.path}/default.json'),
      clientFactory: () => client,
    );
    addTearDown(local.dispose);
    final errors = <String>[];
    local.addListener(() {
      if (local.error != null) errors.add(local.error!);
    });
    await local.check(force: true).timeout(const Duration(seconds: 5));
    expect(local.hasUpdate, isTrue);
    expect(client.uris.map((u) => u.host), ['192.168.31.167', 'github.com']);
    expect(errors, isEmpty);
  });

  for (final changed in [false, true]) {
    test(
      'failed LAN download falls back only to identical GitHub bytes changed=$changed',
      () async {
        final client = _UpdateClient([
          _Reply(200, bytes: utf8.encode(jsonEncode(manifest))),
          _Reply(503),
          _Reply(
            200,
            bytes: utf8.encode(
              jsonEncode({
                ...manifest,
                'url': '$githubUpdateUrl/releases/download/v1/app.apk',
                if (changed) 'sha256': 'a' * 64,
              }),
            ),
          ),
          if (!changed) _Reply(200, bytes: bytes),
        ]);
        final local = AppUpdateController(
          bridge: bridge,
          supported: true,
          cacheRoot: () async => root,
          configFile: () async => File('${root.path}/default.json'),
          clientFactory: () => client,
        );
        addTearDown(local.dispose);
        final visibleErrors = <String>[];
        local.addListener(() {
          if (local.error != null) visibleErrors.add(local.error!);
        });
        await local.check(force: true);
        await local.downloadAndInstall();
        if (changed) {
          expect(bridge.installs, 0);
          expect(local.error, contains('重新检测更新'));
          expect(local.downloadedApk, isNull);
        } else {
          expect(bridge.installs, 1);
          expect(await bridge.file!.readAsBytes(), bytes);
          expect(visibleErrors, isEmpty);
        }
      },
    );
  }

  test('cancelling a LAN download prevents GitHub fallback', () async {
    final client = _UpdateClient([
      _Reply(200, bytes: utf8.encode(jsonEncode(manifest))),
      _Reply(200, bytes: bytes.sublist(1)),
    ]);
    final local = AppUpdateController(
      bridge: bridge,
      supported: true,
      cacheRoot: () async => root,
      configFile: () async => File('${root.path}/default.json'),
      clientFactory: () => client,
    );
    addTearDown(local.dispose);
    await local.check(force: true);
    local.addListener(() {
      if (local.downloading && local.received > 0) local.cancelDownload();
    });
    await local.downloadAndInstall();
    expect(client.uris.length, 2);
    expect(bridge.installs, 0);
    expect(local.error, isNull);
    expect(local.downloadedApk, isNull);
  });

  for (final status in [204, 503, 302]) {
    test(
      'LAN $status silently falls back to GitHub metadata and verified download',
      () async {
        final client = _UpdateClient([
          _Reply(status, location: 'https://other.invalid/metadata'),
          _Reply(
            200,
            bytes: utf8.encode(
              jsonEncode({
                ...manifest,
                'url': '$githubUpdateUrl/releases/download/v1/app.apk',
              }),
            ),
          ),
          _Reply(
            302,
            location: 'https://release-assets.githubusercontent.com/app.apk',
          ),
          _Reply(200, bytes: bytes),
        ]);
        final local = AppUpdateController(
          bridge: bridge,
          supported: true,
          cacheRoot: () async => root,
          configFile: () async => File('${root.path}/default.json'),
          clientFactory: () => client,
        );
        addTearDown(local.dispose);
        final visibleErrors = <String>[];
        local.addListener(() {
          if (local.error != null) visibleErrors.add(local.error!);
        });
        await local.check(force: true);
        expect(local.hasUpdate, isTrue);
        expect(local.serverUrl, defaultUpdateUrl);
        expect(visibleErrors, isEmpty);
        expect(client.uris.map((u) => u.host).take(2), [
          '192.168.31.167',
          'github.com',
        ]);
        await local.downloadAndInstall();
        expect(bridge.installs, 1);
        expect(await bridge.file!.readAsBytes(), bytes);
      },
    );
  }

  test(
    'GitHub metadata and APK redirects produce verified install bytes',
    () async {
      final githubManifest = {
        ...manifest,
        'url': '$githubUpdateUrl/releases/download/v1.0.3-101/app.apk',
      };
      final client = _UpdateClient([
        _Reply(
          302,
          location: 'https://release-assets.githubusercontent.com/metadata',
        ),
        _Reply(200, bytes: utf8.encode(jsonEncode(githubManifest))),
        _Reply(
          302,
          location:
              'https://release-assets.githubusercontent.com/app.apk?token=temporary',
        ),
        _Reply(200, bytes: bytes),
      ]);
      await File(
        '${root.path}/github.json',
      ).writeAsString(jsonEncode({'serverUrl': githubUpdateUrl}));
      final github = AppUpdateController(
        bridge: bridge,
        supported: true,
        cacheRoot: () async => root,
        configFile: () async => File('${root.path}/github.json'),
        clientFactory: () => client,
      );
      addTearDown(github.dispose);
      await github.check(force: true);
      expect(github.hasUpdate, isTrue);
      expect(
        client.uris.first.toString(),
        '$githubUpdateUrl/releases/latest/download/latest.json',
      );
      await github.downloadAndInstall();
      expect(bridge.installs, 1);
      expect(await bridge.file!.readAsBytes(), bytes);
      expect(client.uris.length, 4);
    },
  );

  for (final location in [
    'http://release-assets.githubusercontent.com/app.apk',
    'https://other.invalid/app.apk',
    'https://github.com:8443/app.apk',
  ]) {
    test('GitHub rejects unsafe redirect $location', () async {
      final client = _UpdateClient([_Reply(302, location: location)]);
      await File(
        '${root.path}/github.json',
      ).writeAsString(jsonEncode({'serverUrl': githubUpdateUrl}));
      final github = AppUpdateController(
        bridge: bridge,
        supported: true,
        configFile: () async => File('${root.path}/github.json'),
        clientFactory: () => client,
      );
      addTearDown(github.dispose);
      await github.check(force: true);
      expect(github.hasUpdate, isFalse);
      expect(github.error, isNotNull);
      expect(client.uris.length, 1);
    });
  }

  test(
    'GitHub manifest rejects APK paths outside the application repository',
    () {
      for (final url in [
        'https://github.com/other/repo/releases/download/v1/app.apk',
        'https://release-assets.githubusercontent.com/app.apk',
      ]) {
        expect(
          () => AppRelease.parse(
            {...manifest, 'url': url},
            AppUpdateController.normalizeServer(githubUpdateUrl),
            updates.current!,
          ),
          throwsFormatException,
        );
      }
    },
  );

  test('saved built-in and custom addresses persist', () async {
    for (final saved in [
      defaultUpdateUrl,
      githubUpdateUrl,
      'http://192.168.1.5:8788',
    ]) {
      final config = File('${root.path}/migration.json');
      await config.writeAsString(jsonEncode({'serverUrl': saved}));
      final migrated = AppUpdateController(
        bridge: bridge,
        supported: true,
        configFile: () async => config,
      );
      await migrated.initialize();
      expect(migrated.serverUrl, '$saved/');
      migrated.dispose();
    }
  });
}

class _UpdateClient extends Fake implements HttpClient {
  _UpdateClient(this.replies);
  final List<_Reply> replies;
  final List<Uri> uris = [];
  @override
  set connectionTimeout(Duration? value) {}
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    uris.add(url);
    return _UpdateRequest(replies.removeAt(0));
  }

  @override
  void close({bool force = false}) {}
}

class _HangingLanClient extends _UpdateClient {
  _HangingLanClient(super.replies);
  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    if (url.host == '192.168.31.167') {
      uris.add(url);
      return Completer<HttpClientRequest>().future;
    }
    return super.getUrl(url);
  }
}

class _UpdateRequest extends Fake implements HttpClientRequest {
  _UpdateRequest(this.reply);
  final _Reply reply;
  @override
  bool followRedirects = true;
  @override
  Future<HttpClientResponse> close() async {
    expect(followRedirects, isFalse);
    return reply;
  }
}

class _Reply extends Stream<List<int>> implements HttpClientResponse {
  _Reply(this.statusCode, {this.bytes = const [], String? location})
    : headers = _UpdateHeaders(location);
  final List<int> bytes;
  @override
  final int statusCode;
  @override
  final HttpHeaders headers;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UpdateHeaders extends Fake implements HttpHeaders {
  _UpdateHeaders(this.location);
  final String? location;
  @override
  String? value(String name) =>
      name == HttpHeaders.locationHeader ? location : null;
}

class _Bridge implements AndroidUpdateBridge {
  _Bridge({this.channel = 'release'});
  final String channel;
  int installs = 0;
  File? file;
  bool allowed = true;
  @override
  Future<InstalledAppVersion> info() async => InstalledAppVersion(
    name: '1.0.1',
    code: 100,
    builtAt: DateTime(2026, 10, 3),
    channel: channel,
  );
  @override
  Future<bool> install(File apk, int versionCode) async {
    expect(versionCode, 101);
    installs++;
    file = apk;
    return allowed;
  }
}

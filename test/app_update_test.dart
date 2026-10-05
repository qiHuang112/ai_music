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

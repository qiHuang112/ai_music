import 'dart:async';
import 'dart:io';

import 'package:ai_music/src/application/music_controller.dart';
import 'package:ai_music/src/data/music_resolver.dart';
import 'package:ai_music/src/domain/music_models.dart';
import 'package:ai_music/src/playback/music_audio_handler.dart';
import 'package:ai_music/src/presentation/song_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _track = Track(
  id: 'song',
  title: 'Song',
  artist: 'Artist',
  album: 'Album',
);
const _channel = MethodChannel('ai_music/share');

void main() {
  testWidgets(
    'cached sharing opens the system chooser without preparing again',
    (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('share_ui_'),
      ))!;
      final file = File('${root.path}/song.mp3');
      await tester.runAsync(() => file.writeAsBytes([1, 2, 3]));
      final controller = _Controller(file: file);
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (value) {
                context = value;
                return const Text('Library');
              },
            ),
          ),
        ),
      );
      await tester.runAsync(() => shareSong(context, controller, _track));
      expect(calls.single.method, 'file');
      expect(calls.single.arguments['path'], file.path);
      expect(controller.preparations, 0);
      expect(find.byType(AlertDialog), findsNothing);
      controller.dispose();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _channel,
        null,
      );
      await tester.runAsync(() => root.delete(recursive: true));
    },
  );

  for (final fail in [false, true]) {
    testWidgets(
      'preparing share ${fail ? 'failure' : 'cancellation'} closes only its progress route and never opens a chooser',
      (tester) async {
        final controller = _Controller();
        var calls = 0;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          _channel,
          (_) async {
            calls++;
            return null;
          },
        );
        Future<void>? share;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => Scaffold(
                          body: TextButton(
                            onPressed: () {
                              share = shareSong(context, controller, _track);
                            },
                            child: const Text('Share'),
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('Library'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Library'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Share'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text('正在准备分享…'), findsOneWidget);
        if (fail) {
          controller.prepared.completeError(StateError('offline'));
        } else {
          await tester.tap(find.text('取消'));
          await tester.pump();
          expect(controller.cancelled, isTrue);
          controller.prepared.complete(File('/unused/late.mp3'));
        }
        await share;
        await tester.pumpAndSettle();
        expect(calls, 0);
        expect(
          find.text('Share'),
          findsOneWidget,
          reason: 'The underlying detail route remains open',
        );
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('分享失败，请重试'), fail ? findsOneWidget : findsNothing);
        expect(tester.takeException(), isNull);
        controller.dispose();
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          _channel,
          null,
        );
      },
    );
  }
}

class _Controller extends MusicController {
  _Controller({this.file}) : super(audioHandler: MusicAudioHandler());
  final File? file;
  final prepared = Completer<File>();
  int preparations = 0;
  bool cancelled = false;
  @override
  Future<File?> cachedFileForSharing(
    Track track, {
    MusicSearchCandidate? candidate,
  }) async => file;
  @override
  Future<File> prepareTrackForSharing(
    Track track, {
    MusicSearchCandidate? candidate,
    required bool Function() isCancelled,
    required void Function(VoidCallback cancel) onCancelReady,
  }) {
    preparations++;
    onCancelReady(() => cancelled = true);
    return prepared.future;
  }
}

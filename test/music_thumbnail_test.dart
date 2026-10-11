import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_music/src/presentation/music_thumbnail.dart';
import 'package:ai_music/src/presentation/native_artwork_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
  const legacyCover =
      'http://p1.music.126.net/_B1Fn_Z1WxHzqGLzLZDf-w==/109951163263882447.jpg';

  testWidgets('legacy Mayday artwork uses the provider request and decodes', (
    tester,
  ) async {
    final client = _ArtworkClient((uri, headers) {
      // Reproduce a CDN refusing an insecure or unattributed cover request.
      return uri.scheme == 'https' &&
          headers.values['Referer'] == 'https://music.163.com/';
    });
    debugNetworkImageHttpClientProvider = () => client;
    addTearDown(() => debugNetworkImageHttpClientProvider = null);
    await tester.pumpWidget(
      MaterialApp(
        home: MusicThumbnail(uri: Uri.parse(legacyCover), label: '五月天40分钟'),
      ),
    );
    for (var attempt = 0; attempt < 10; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (find.byType(RawImage).evaluate().isNotEmpty) break;
    }
    expect(
      client.uris.single.toString(),
      legacyCover.replaceFirst('http:', 'https:'),
    );
    expect(client.lastHeaders.values['User-Agent'], 'Mozilla/5.0');
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    expect(
      find.byKey(const ValueKey('music-thumbnail-placeholder')),
      findsNothing,
    );
    debugNetworkImageHttpClientProvider = null;
    expect(tester.takeException(), isNull);
  });

  testWidgets('LAN HTTP covers retain their URL and explicit headers', (
    tester,
  ) async {
    final client = _ArtworkClient((_, _) => true);
    debugNetworkImageHttpClientProvider = () => client;
    addTearDown(() => debugNetworkImageHttpClientProvider = null);
    const url = 'http://192.168.31.167:8788/covers/test.png';
    await tester.pumpWidget(
      MaterialApp(
        home: MusicThumbnail(
          uri: Uri.parse(url),
          headers: const {'X-Cover': 'local'},
        ),
      ),
    );
    for (var attempt = 0; attempt < 10; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (find.byType(RawImage).evaluate().isNotEmpty) break;
    }
    expect(client.uris.single.toString(), url);
    expect(client.lastHeaders.values, {'X-Cover': 'local'});
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    debugNetworkImageHttpClientProvider = null;
    expect(tester.takeException(), isNull);
  });

  for (final available in [true, false]) {
    testWidgets(
      'NetEase 403 retries one resized alternate CDN, available=$available',
      (tester) async {
        final pixels = (58 * tester.view.devicePixelRatio).ceil().clamp(1, 512);
        final client = _ArtworkClient(
          (uri, _) =>
              available &&
              uri.host == 'p2.music.126.net' &&
              uri.queryParameters['param'] == '${pixels}y$pixels',
        );
        debugNetworkImageHttpClientProvider = () => client;
        addTearDown(() => debugNetworkImageHttpClientProvider = null);
        await tester.pumpWidget(
          MaterialApp(home: MusicThumbnail(uri: Uri.parse(legacyCover))),
        );
        for (var attempt = 0; attempt < 10; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(client.uris.map((u) => u.host), [
          'p1.music.126.net',
          'p2.music.126.net',
        ]);
        expect(client.lastHeaders.values['Referer'], 'https://music.163.com/');
        expect(
          find.byType(RawImage),
          available ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const ValueKey('music-thumbnail-placeholder')),
          available ? findsNothing : findsOneWidget,
        );
        debugNetworkImageHttpClientProvider = null;
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Android 403 uses native artwork once and decodes for both tiles',
    (tester) async {
      final client = _ArtworkClient((_, _) => false);
      debugNetworkImageHttpClientProvider = () => client;
      addTearDown(() => debugNetworkImageHttpClientProvider = null);
      var requests = 0;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(NativeArtworkImage.channel, (
        call,
      ) async {
        requests++;
        expect(call.method, 'load');
        final uri = Uri.parse((call.arguments as Map)['url'] as String);
        expect(uri.scheme, 'https');
        expect(uri.host, 'p2.music.126.net');
        expect(uri.queryParameters['param'], isNotNull);
        return _ArtworkResponse(true).bytes;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          NativeArtworkImage.channel,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Row(
            children: [
              for (var i = 0; i < 2; i++)
                MusicThumbnail(uri: Uri.parse(legacyCover)),
            ],
          ),
        ),
      );
      for (var attempt = 0; attempt < 15; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (find.byType(RawImage).evaluate().length == 2) break;
      }
      expect(requests, 1);
      expect(client.uris.map((u) => u.host), ['p1.music.126.net']);
      expect(find.byType(RawImage), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('music-thumbnail-placeholder')),
        findsNothing,
      );
      debugNetworkImageHttpClientProvider = null;
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}

class _ArtworkClient extends Fake implements HttpClient {
  _ArtworkClient(this.accept);
  final bool Function(Uri, _ArtworkHeaders) accept;
  final uris = <Uri>[];
  late _ArtworkHeaders lastHeaders;
  @override
  Future<HttpClientRequest> getUrl(Uri uri) async {
    uris.add(uri);
    lastHeaders = _ArtworkHeaders();
    return _ArtworkRequest(() => accept(uri, lastHeaders), lastHeaders);
  }
}

class _ArtworkHeaders extends Fake implements HttpHeaders {
  final values = <String, Object>{};
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = value;
  }
}

class _ArtworkRequest extends Fake implements HttpClientRequest {
  _ArtworkRequest(this.accept, this.headers);
  final bool Function() accept;
  @override
  final _ArtworkHeaders headers;
  @override
  Future<HttpClientResponse> close() async => _ArtworkResponse(accept());
}

class _ArtworkResponse extends Stream<List<int>> implements HttpClientResponse {
  _ArtworkResponse(this.accepted);
  final bool accepted;
  final bytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAEElEQVR4nGP4z8AARwzEcQCukw/x0F8jngAAAABJRU5ErkJggg==',
  );
  @override
  int get statusCode => accepted ? HttpStatus.ok : HttpStatus.forbidden;
  @override
  int get contentLength => bytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
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

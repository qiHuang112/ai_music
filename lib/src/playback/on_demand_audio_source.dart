import 'dart:io';

import 'package:just_audio/just_audio.dart';

class OnDemandAudioSource extends StreamAudioSource {
  OnDemandAudioSource({
    required this.prepare,
    required super.tag,
    this.waitForNext = const Duration(seconds: 3),
  });

  final Future<File> Function() prepare;
  final Duration waitForNext;
  Future<File>? _pending;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    late final File file;
    try {
      file = await (_pending ??= prepare()).timeout(waitForNext);
    } catch (_) {
      _pending = null;
      rethrow;
    }
    if (!await file.exists()) {
      throw const FileSystemException('Prepared audio is missing');
    }
    final length = await file.length();
    final from = (start ?? 0).clamp(0, length);
    final to = (end ?? length).clamp(from, length);
    final extension = file.uri.pathSegments.last.toLowerCase();
    final contentType = extension.endsWith('.flac')
        ? 'audio/flac'
        : extension.endsWith('.m4a') || extension.endsWith('.mp4')
        ? 'audio/mp4'
        : extension.endsWith('.ogg')
        ? 'audio/ogg'
        : extension.endsWith('.wav')
        ? 'audio/wav'
        : extension.endsWith('.aac')
        ? 'audio/aac'
        : extension.endsWith('.ape')
        ? 'audio/ape'
        : 'audio/mpeg';
    return StreamAudioResponse(
      sourceLength: length,
      contentLength: to - from,
      offset: from,
      stream: file.openRead(from, to),
      contentType: contentType,
    );
  }
}

// ignore_for_file: experimental_member_use

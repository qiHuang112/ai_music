enum MusicAppFailureKind {
  connectionTimeout,
  receiveTimeout,
  sendTimeout,
  connectionFailed,
  badResponse,
  cancelled,
  badCertificate,
  trackNotInLibrary,
  unknown,
}

class MusicAppException implements Exception {
  const MusicAppException(this.kind, this.message, {this.statusCode});

  final MusicAppFailureKind kind;
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

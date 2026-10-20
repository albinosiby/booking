class AppException implements Exception {
  const AppException(this.message, {this.code = 'UNKNOWN'});
  final String message;
  final String code;
  @override
  String toString() => message;
}

bool accessFailure(Object error) =>
    error is AppException &&
    (error.code == 'FORBIDDEN' || error.code == 'UNAUTHENTICATED');

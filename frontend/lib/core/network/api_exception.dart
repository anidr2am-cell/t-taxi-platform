enum ApiFailureKind {
  unauthorized,
  forbidden,
  notFound,
  validation,
  conflict,
  unavailable,
  timeout,
  invalidResponse,
  server,
  unknown,
}

class ApiException implements Exception {
  const ApiException(
    this.kind, {
    this.statusCode,
    this.errorCode,
    this.message,
    this.details,
  });

  final ApiFailureKind kind;
  final int? statusCode;
  final String? errorCode;
  final String? message;
  final Map<String, dynamic>? details;

  @override
  String toString() => message ?? 'ApiException($kind)';
}

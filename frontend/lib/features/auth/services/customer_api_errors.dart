import '../../../core/network/api_exception.dart';

bool isCustomerUnauthorized(Object error) {
  if (error is ApiException) {
    return error.kind == ApiFailureKind.unauthorized;
  }
  try {
    final dynamic typed = error;
    return typed.statusCode == 401;
  } catch (_) {
    return false;
  }
}

int? customerApiStatusCode(Object error) {
  if (error is ApiException) {
    return error.statusCode;
  }
  try {
    final dynamic typed = error;
    final statusCode = typed.statusCode;
    if (statusCode is int) {
      return statusCode;
    }
  } catch (_) {}
  return null;
}

String customerApiErrorMessage(
  Object error, {
  required String fallback,
}) {
  if (error is ApiException) {
    final message = error.message?.trim();
    if (message != null && message.isNotEmpty) {
      return message;
    }
  }
  try {
    final dynamic typed = error;
    final message = typed.message;
    if (message is String && message.trim().isNotEmpty) {
      return message.trim();
    }
  } catch (_) {}
  return fallback;
}

/// Maps errors to safe user-visible text without exposing exception types.
String userFacingError(
  Object err, {
  String? fallback,
}) {
  try {
    final dynamic typed = err;
    final message = typed.message;
    if (message is String) {
      final trimmed = message.trim();
      if (trimmed.isNotEmpty && !looksLikeInternalApiMessage(trimmed)) {
        return trimmed;
      }
    }
  } catch (_) {}

  final text = err.toString().trim();
  if (text.isEmpty ||
      text.startsWith('Instance of') ||
      text.contains('Stack trace') ||
      looksLikeInternalApiMessage(text) ||
      text.contains('failed host lookup') ||
      text.contains('SocketException') ||
      text.contains('Failed to fetch') ||
      text.contains('ClientException') ||
      text.contains('Connection refused') ||
      text.contains('NetworkError') ||
      text.contains('XMLHttpRequest')) {
    return fallback ?? 'ui_generic_error';
  }
  return text;
}

bool looksLikeInternalApiMessage(String message) {
  final normalized = message.toLowerCase();
  return normalized.contains('data truncated') ||
      normalized.contains("column '") ||
      normalized.contains("table '") ||
      normalized.contains('sql syntax') ||
      normalized.contains('er_') ||
      normalized.contains('settlement not found') ||
      normalized.contains('internal server error') ||
      normalized.contains('an unexpected error occurred');
}

String driverEndTripFailedMessage(String languageCode) {
  switch (languageCode) {
    case 'ko':
      return '운행 종료 처리 중 문제가 발생했습니다. 잠시 후 다시 시도하거나 관리자에게 문의해 주세요.';
    case 'th':
      return 'ไม่สามารถสิ้นสุดการเดินทางได้ กรุณาลองอีกครั้งหรือติดต่อผู้ดูแลระบบ';
    default:
      return 'We could not complete the trip. Please try again or contact an administrator.';
  }
}

String driverSettlementLoadFailedMessage(String languageCode) {
  switch (languageCode) {
    case 'ko':
      return '정산 정보를 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.';
    case 'th':
      return 'ไม่สามารถโหลดข้อมูลการชำระเงินได้ กรุณาลองอีกครั้ง';
    default:
      return 'We could not load the settlement information. Please try again.';
  }
}

String driverSettlementApiErrorMessage({
  required String message,
  String? errorCode,
  required String languageCode,
}) {
  if (errorCode == 'RECEIPT_ALREADY_APPROVED' ||
      errorCode == 'INVALID_FILE_TYPE' ||
      errorCode == 'VALIDATION_ERROR') {
    return message;
  }

  if (errorCode == 'SETTLEMENT_NOT_FOUND' ||
      looksLikeInternalApiMessage(message)) {
    return driverSettlementLoadFailedMessage(languageCode);
  }

  return message;
}

String driverApiErrorMessage({
  required String message,
  String? errorCode,
  required String languageCode,
  bool preferEndTripFailure = false,
}) {
  if (errorCode == 'INVALID_STATUS_TRANSITION' ||
      errorCode == 'BOOKING_NOT_FOUND' ||
      errorCode == 'BOOKING_NOT_ACCESSIBLE') {
    return message;
  }

  if (preferEndTripFailure &&
      (errorCode == 'INTERNAL_SERVER_ERROR' ||
          looksLikeInternalApiMessage(message))) {
    return driverEndTripFailedMessage(languageCode);
  }

  if (looksLikeInternalApiMessage(message)) {
    return driverEndTripFailedMessage(languageCode);
  }

  return message;
}

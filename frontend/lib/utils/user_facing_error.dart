/// Maps errors to safe user-visible text without exposing exception types.
String userFacingError(
  Object err, {
  String? fallback,
  String languageCode = 'en',
}) {
  final validation = validationErrorMessage(err, languageCode: languageCode);
  if (validation != null) return validation;

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

String? validationErrorMessage(Object err, {String languageCode = 'en'}) {
  try {
    final dynamic typed = err;
    final errorCode = typed.errorCode;
    final errors = typed.errors;
    if (errorCode != 'VALIDATION_ERROR') {
      return null;
    }
    if (errors is! List || errors.isEmpty) {
      return _validationFallback(languageCode);
    }
    final fields = errors
        .map((item) {
          try {
            final dynamic detail = item;
            return (
              field: (detail.field as String? ?? '').trim(),
              type: (detail.type as String? ?? '').trim(),
            );
          } catch (_) {
            return (field: '', type: '');
          }
        })
        .where((item) => item.field.isNotEmpty || item.type.isNotEmpty)
        .toList(growable: false);
    if (fields.isEmpty) return _validationFallback(languageCode);
    return _validationDetailMessage(
      fields.first.field,
      fields.first.type,
      languageCode,
    );
  } catch (_) {
    return null;
  }
}

String _validationDetailMessage(
  String field,
  String type,
  String languageCode,
) {
  final normalized = field.toLowerCase();
  if (normalized == 'servicedatefrom' || normalized == 'datefrom') {
    return switch (languageCode) {
      'ko' => '시작 날짜는 YYYY-MM-DD 형식으로 입력해 주세요.',
      'th' => 'กรุณาระบุวันที่เริ่มต้นในรูปแบบ YYYY-MM-DD',
      _ => 'Please enter the start date in YYYY-MM-DD format.',
    };
  }
  if (normalized == 'servicedateto' || normalized == 'dateto') {
    if (type == 'date.range') {
      return switch (languageCode) {
        'ko' => '종료 날짜는 시작 날짜보다 빠를 수 없습니다.',
        'th' => 'วันที่สิ้นสุดต้องไม่อยู่ก่อนวันที่เริ่มต้น',
        _ => 'The end date cannot be earlier than the start date.',
      };
    }
    return switch (languageCode) {
      'ko' => '종료 날짜는 YYYY-MM-DD 형식으로 입력해 주세요.',
      'th' => 'กรุณาระบุวันที่สิ้นสุดในรูปแบบ YYYY-MM-DD',
      _ => 'Please enter the end date in YYYY-MM-DD format.',
    };
  }
  if (normalized == 'customer.email' || normalized.endsWith('.email')) {
    return switch (languageCode) {
      'ko' => '이메일 형식이 올바르지 않습니다.',
      'th' => 'รูปแบบอีเมลไม่ถูกต้อง',
      _ => 'Please enter a valid email address.',
    };
  }
  if (normalized == 'scheduledpickupat') {
    return switch (languageCode) {
      'ko' => '탑승 날짜와 시간을 확인해 주세요.',
      'th' => 'กรุณาตรวจสอบวันและเวลารับ',
      _ => 'Please check the pickup date and time.',
    };
  }
  if (normalized.contains('flight')) {
    return switch (languageCode) {
      'ko' => '항공편 번호를 확인해 주세요.',
      'th' => 'กรุณาตรวจสอบหมายเลขเที่ยวบิน',
      _ => 'Please check the flight number.',
    };
  }
  return _validationFallback(languageCode);
}

String _validationFallback(String languageCode) {
  return switch (languageCode) {
    'ko' => '입력한 내용을 다시 확인해 주세요.',
    'th' => 'กรุณาตรวจสอบข้อมูลที่กรอกอีกครั้ง',
    _ => 'Please check the information you entered.',
  };
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
      normalized == 'validation failed' ||
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

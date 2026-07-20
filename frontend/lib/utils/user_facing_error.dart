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
      text.contains('SyntaxError') ||
      text.contains('JSON Parse error') ||
      text.contains('Unexpected token') ||
      text.contains('FormatException') ||
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
  if (errorCode == 'INVALID_STATUS_TRANSITION') {
    return switch (languageCode) {
      'ko' => '현재 운행 단계에서는 이 작업을 처리할 수 없습니다. 상태를 새로고침해 주세요.',
      'th' => 'ไม่สามารถดำเนินการในขั้นตอนปัจจุบันได้ กรุณารีเฟรชสถานะ',
      'zh' => '当前行程阶段无法执行此操作。请刷新状态。',
      'ja' => '現在の運行段階ではこの操作を処理できません。状態を更新してください。',
      _ =>
        'This action cannot be handled at the current trip stage. Please refresh the status.',
    };
  }

  if (errorCode == 'BOOKING_NOT_ASSIGNED_TO_DRIVER' ||
      errorCode == 'NO_ACTIVE_ASSIGNMENT') {
    return switch (languageCode) {
      'ko' => '현재 기사에게 배정된 예약이 아닙니다.',
      'th' => 'งานนี้ไม่ได้ถูกมอบหมายให้คนขับปัจจุบัน',
      'zh' => '此预订未分配给当前司机。',
      'ja' => 'この予約は現在のドライバーに割り当てられていません。',
      _ => 'This booking is not assigned to the current driver.',
    };
  }

  if (errorCode == 'BOOKING_NOT_FOUND' ||
      errorCode == 'BOOKING_NOT_ACCESSIBLE') {
    return switch (languageCode) {
      'ko' => '예약 정보를 찾을 수 없습니다. 상태를 새로고침해 주세요.',
      'th' => 'ไม่พบข้อมูลงาน กรุณารีเฟรชสถานะ',
      'zh' => '找不到预订信息。请刷新状态。',
      'ja' => '予約情報が見つかりません。状態を更新してください。',
      _ => 'Booking information could not be found. Please refresh the status.',
    };
  }

  if (errorCode == 'DRIVER_STANDBY_TOO_EARLY') {
    return switch (languageCode) {
      'ko' => '아직 Stand by를 확정할 수 없습니다. 예약 기준 1시간 전부터 가능합니다.',
      'th' =>
        'ยังไม่ถึงเวลายืนยัน Stand by สามารถยืนยันได้ก่อนเวลานัดหมาย 1 ชั่วโมง',
      'zh' => '尚未到 Stand by 确认时间。可在预约时间前 1 小时确认。',
      'ja' => 'まだ Stand by を確認できません。予約時刻の1時間前から確認できます。',
      _ =>
        'Standby is not available yet. You can confirm from one hour before the appointment time.',
    };
  }

  if (errorCode == 'DRIVER_STANDBY_REFERENCE_TIME_MISSING') {
    return switch (languageCode) {
      'ko' => '예약 기준 시간을 찾을 수 없습니다. 관리자에게 문의해 주세요.',
      'th' => 'ไม่พบเวลานัดหมายของงานนี้ กรุณาติดต่อแอดมิน',
      'zh' => '找不到此行程的预约时间。请联系管理员。',
      'ja' => 'この仕事の予約時刻が見つかりません。管理者に連絡してください。',
      _ => 'Appointment time was not found. Please contact admin.',
    };
  }

  if (errorCode == 'DRIVER_ASSIGNMENT_NOT_ACTIVE' ||
      errorCode == 'DRIVER_BOOKING_STATUS_NOT_ALLOWED' ||
      errorCode == 'BOOKING_NOT_ACCEPTABLE') {
    return switch (languageCode) {
      'ko' => '이 예약은 현재 운행 확정을 할 수 없습니다. 관리자에게 상태 확인을 요청해 주세요.',
      'th' =>
        'ไม่สามารถยืนยันงานนี้ได้ กรุณาติดต่อแอดมินเพื่อตรวจสอบสถานะการจอง',
      'zh' => '当前无法确认此订单。请联系管理员检查订单状态。',
      'ja' => '現在この予約は確認できません。管理者に予約状態の確認を依頼してください。',
      _ =>
        'This booking cannot be confirmed now. Please contact admin to check the booking status.',
    };
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

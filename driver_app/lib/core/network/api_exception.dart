enum ApiFailureKind {
  invalidCredentials,
  unauthorized,
  forbidden,
  notFound,
  standbyTooEarly,
  standbyReferenceTimeMissing,
  bookingTimeConflict,
  alreadyClaimed,
  invalidStatusTransition,
  releaseNotAllowed,
  assignmentAlreadyReleased,
  bookingNotAssigned,
  validation,
  invalidFileType,
  fileTooLarge,
  vehiclePlateAlreadyRegistered,
  conflict,
  unavailable,
  timeout,
  invalidResponse,
  server,
  configuration,
  unknown,
}

class ApiException implements Exception {
  const ApiException(this.kind, {this.statusCode, this.errorCode});

  final ApiFailureKind kind;
  final int? statusCode;
  final String? errorCode;

  String get userMessage => switch (kind) {
    ApiFailureKind.invalidCredentials => '계정 또는 비밀번호를 확인해 주세요.',
    ApiFailureKind.unauthorized => '로그인이 만료되었습니다. 다시 로그인해 주세요.',
    ApiFailureKind.forbidden => '예약을 수락할 수 없습니다. 관리자에게 문의해 주세요.',
    ApiFailureKind.notFound => '예약 정보를 찾을 수 없습니다.',
    ApiFailureKind.standbyTooEarly => '아직 대기 확정 시간이 아닙니다. 대기 가능 시간을 확인해 주세요.',
    ApiFailureKind.standbyReferenceTimeMissing =>
      '대기 확정 기준 시간을 확인할 수 없습니다. 관리자에게 문의해 주세요.',
    ApiFailureKind.bookingTimeConflict => '기존 운행과 시간이 겹쳐 이 콜을 받을 수 없습니다.',
    ApiFailureKind.alreadyClaimed => '다른 기사가 먼저 이 콜을 배정받았습니다.',
    ApiFailureKind.invalidStatusTransition =>
      '운행 상태가 이미 변경되었습니다. 최신 정보를 다시 확인해 주세요.',
    ApiFailureKind.releaseNotAllowed => '현재 이 배정을 반납할 수 없습니다.',
    ApiFailureKind.assignmentAlreadyReleased => '이미 반납된 배정입니다.',
    ApiFailureKind.bookingNotAssigned => '현재 기사에게 배정된 예약이 아닙니다.',
    ApiFailureKind.validation => '입력 내용을 다시 확인해 주세요.',
    ApiFailureKind.invalidFileType => '지원하지 않는 파일 형식입니다.',
    ApiFailureKind.fileTooLarge => '파일 크기가 너무 큽니다. 더 작은 파일을 선택해 주세요.',
    ApiFailureKind.vehiclePlateAlreadyRegistered => '이미 등록된 차량 번호입니다.',
    ApiFailureKind.conflict => '예약 상태가 변경되었습니다. 최신 정보를 다시 확인해 주세요.',
    ApiFailureKind.unavailable => '서버에 연결할 수 없습니다. 네트워크를 확인해 주세요.',
    ApiFailureKind.timeout => '요청 시간이 초과되었습니다. 잠시 후 다시 시도해 주세요.',
    ApiFailureKind.invalidResponse => '서버 응답을 처리할 수 없습니다.',
    ApiFailureKind.server => '일시적인 오류가 발생했습니다. 다시 시도해 주세요.',
    ApiFailureKind.configuration => '이 환경의 API가 설정되지 않았습니다.',
    ApiFailureKind.unknown => '알 수 없는 오류가 발생했습니다.',
  };

  @override
  String toString() => 'ApiException($kind)';
}

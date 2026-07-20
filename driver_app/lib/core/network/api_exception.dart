enum ApiFailureKind {
  invalidCredentials,
  unauthorized,
  forbidden,
  notFound,
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
    ApiFailureKind.conflict => '예약 상태가 변경되었습니다. 최신 정보를 다시 확인해 주세요.',
    ApiFailureKind.unavailable => '서버에 연결할 수 없습니다. 네트워크를 확인해 주세요.',
    ApiFailureKind.timeout => '요청 시간이 초과되었습니다. 잠시 후 다시 시도해 주세요.',
    ApiFailureKind.invalidResponse => '서버 응답을 처리할 수 없습니다.',
    ApiFailureKind.server => '서버 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.',
    ApiFailureKind.configuration => '이 환경의 API가 설정되지 않았습니다.',
    ApiFailureKind.unknown => '알 수 없는 오류가 발생했습니다.',
  };

  @override
  String toString() => 'ApiException($kind)';
}

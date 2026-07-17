import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/utils/user_facing_error.dart';

void main() {
  test('looksLikeInternalApiMessage detects mysql truncation text', () {
    expect(
      looksLikeInternalApiMessage(
        "Data truncated for column 'status' at row 1",
      ),
      isTrue,
    );
    expect(
      looksLikeInternalApiMessage('Invalid booking status transition'),
      isFalse,
    );
  });

  test('driverEndTripFailedMessage supports ko en th', () {
    expect(driverEndTripFailedMessage('ko'), contains('운행 종료 처리 중'));
    expect(
      driverEndTripFailedMessage('en'),
      contains('We could not complete the trip'),
    );
    expect(
      driverEndTripFailedMessage('th'),
      contains('ไม่สามารถสิ้นสุดการเดินทางได้'),
    );
  });

  test('driverApiErrorMessage maps invalid trip state safely', () {
    expect(
      driverApiErrorMessage(
        message: 'Invalid booking status transition',
        errorCode: 'INVALID_STATUS_TRANSITION',
        languageCode: 'en',
        preferEndTripFailure: true,
      ),
      contains('current trip stage'),
    );
  });

  test('driverApiErrorMessage hides internal end-trip failures', () {
    expect(
      driverApiErrorMessage(
        message: "Data truncated for column 'status' at row 1",
        errorCode: 'INTERNAL_SERVER_ERROR',
        languageCode: 'ko',
        preferEndTripFailure: true,
      ),
      driverEndTripFailedMessage('ko'),
    );
  });

  test('driverSettlementApiErrorMessage hides settlement not found', () {
    expect(
      driverSettlementApiErrorMessage(
        message: 'Settlement not found',
        errorCode: 'SETTLEMENT_NOT_FOUND',
        languageCode: 'en',
      ),
      driverSettlementLoadFailedMessage('en'),
    );
  });

  test('userFacingError does not return raw database text', () {
    expect(
      userFacingError(
        _MessageError("Data truncated for column 'status' at row 1"),
        fallback: 'fallback',
      ),
      'fallback',
    );
  });
}

class _MessageError implements Exception {
  _MessageError(this.message);

  final String message;
}

import 'package:flutter_test/flutter_test.dart';
import 'package:tride_driver/core/network/api_exception.dart';
import 'package:tride_driver/features/auth/data/auth_models.dart';

void main() {
  test('login request serializes a phone account', () {
    expect(buildLoginRequest(loginId: ' 0812345678 ', password: 'pass'), {
      'phone': '0812345678',
      'password': 'pass',
    });
  });

  test('login request serializes an email account', () {
    expect(buildLoginRequest(loginId: 'driver@example.com', password: 'pass'), {
      'email': 'driver@example.com',
      'password': 'pass',
    });
  });

  test('login response parses access and refresh token fields', () {
    final session = AuthSession.fromEnvelope({
      'success': true,
      'data': {
        'accessToken': 'access',
        'refreshToken': 'refresh',
        'expiresIn': 3600,
        'user': {
          'id': 9,
          'role': 'DRIVER',
          'isActive': true,
          'name': 'Driver',
          'phone': '0800000000',
          'email': null,
        },
      },
    });
    expect(session.accessToken, 'access');
    expect(session.refreshToken, 'refresh');
    expect(session.expiresIn, 3600);
    expect(session.user.role, 'DRIVER');
  });

  test('missing token is rejected as an invalid response', () {
    expect(
      () => AuthSession.fromEnvelope({
        'success': true,
        'data': {
          'user': {'id': 9, 'role': 'DRIVER', 'isActive': true},
        },
      }),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.invalidResponse,
        ),
      ),
    );
  });
}

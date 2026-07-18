import 'package:flutter_test/flutter_test.dart';
import 'package:tride_driver/core/network/api_exception.dart';
import 'package:tride_driver/features/auth/data/auth_models.dart';

Map<String, dynamic> backendUser() => {
  'id': 9,
  'email': 'driver@example.com',
  'role': 'DRIVER',
  'name': 'Driver',
  'phone': '0800000000',
  'locale': 'th',
  'isActive': true,
};

void expectInvalidResponse(void Function() parse) {
  expect(
    parse,
    throwsA(
      isA<ApiException>().having(
        (error) => error.kind,
        'kind',
        ApiFailureKind.invalidResponse,
      ),
    ),
  );
}

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

  test('parses the backend login response shape', () {
    final session = AuthSession.fromEnvelope({
      'success': true,
      'message': 'Login successful',
      'data': {
        'user': backendUser(),
        'accessToken': 'access',
        'refreshToken': 'refresh',
        'expiresIn': 3600,
      },
    });
    expect(session.accessToken, 'access');
    expect(session.refreshToken, 'refresh');
    expect(session.expiresIn, 3600);
    expect(session.user.id, 9);
    expect(session.user.role, 'DRIVER');
    expect(session.user.isActive, isTrue);
  });

  test('parses the backend auth me user shape', () {
    final user = DriverUser.fromJson(backendUser());
    expect(user.id, 9);
    expect(user.role, 'DRIVER');
    expect(user.isActive, isTrue);
    expect(user.name, 'Driver');
  });

  test('rejects a non-integer user ID', () {
    expectInvalidResponse(
      () => DriverUser.fromJson({...backendUser(), 'id': '9'}),
    );
    expectInvalidResponse(
      () => DriverUser.fromJson({...backendUser(), 'id': 9.5}),
    );
  });

  test('parses the backend role without changing case', () {
    final user = DriverUser.fromJson(backendUser());
    expect(user.role, 'DRIVER');
  });

  test('parses the backend isActive boolean field', () {
    final user = DriverUser.fromJson({...backendUser(), 'isActive': false});
    expect(user.isActive, isFalse);
    expectInvalidResponse(
      () => DriverUser.fromJson({...backendUser(), 'isActive': 1}),
    );
  });

  test('requires a non-empty accessToken', () {
    for (final accessToken in [null, '']) {
      expectInvalidResponse(
        () => AuthSession.fromEnvelope({
          'success': true,
          'data': {'user': backendUser(), 'accessToken': accessToken},
        }),
      );
    }
  });

  test('accepts an omitted refreshToken without inventing one', () {
    final session = AuthSession.fromEnvelope({
      'success': true,
      'data': {'user': backendUser(), 'accessToken': 'access'},
    });
    expect(session.refreshToken, isNull);
  });
}

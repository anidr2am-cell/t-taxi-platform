import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/account/services/mileage_api_service.dart';
import 'package:frontend/features/auth/models/auth_session.dart';
import 'package:frontend/features/auth/models/auth_user.dart';
import 'package:frontend/features/auth/services/auth_token_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('getMileageBalance returns balance from API response', () async {
    final storage = AuthTokenStorage();
    await storage.saveSession(
      const AuthSession(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        user: AuthUser(id: 1, role: 'CUSTOMER', email: 'user@example.com'),
      ),
    );

    final service = MileageApiService(
      client: MockClient((request) async {
        expect(
          request.url.path,
          '/api/v1/customer/mileage',
        );
        expect(request.headers['Authorization'], 'Bearer access-token');
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {'balance': 1250},
          }),
          200,
        );
      }),
      tokenStorage: storage,
      baseUrl: 'http://localhost:3000',
    );

    final result = await service.getMileageBalance();
    expect(result.balance, 1250);
  });

  test('getMileageBalance throws when not authenticated', () async {
    final service = MileageApiService(
      client: MockClient((_) async => http.Response('{}', 500)),
      baseUrl: 'http://localhost:3000',
    );

    expect(
      () => service.getMileageBalance(),
      throwsA(isA<MileageApiException>()),
    );
  });

  test('getMileageBalance throws on API error response', () async {
    final storage = AuthTokenStorage();
    await storage.saveSession(
      const AuthSession(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        user: AuthUser(id: 1, role: 'CUSTOMER', email: 'user@example.com'),
      ),
    );

    final service = MileageApiService(
      client: MockClient((_) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'message': 'Server error',
          }),
          500,
        );
      }),
      tokenStorage: storage,
      baseUrl: 'http://localhost:3000',
    );

    expect(
      () => service.getMileageBalance(),
      throwsA(
        predicate<MileageApiException>((error) => error.message == 'Server error'),
      ),
    );
  });
}

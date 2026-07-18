import 'package:flutter_test/flutter_test.dart';
import 'package:tride_driver/core/network/api_exception.dart';
import 'package:tride_driver/core/storage/secure_token_storage.dart';
import 'package:tride_driver/features/auth/data/auth_repository.dart';

import 'test_fakes.dart';

void main() {
  test('login stores tokens and returns an authenticated session', () async {
    final api = FakeAuthApi();
    final storage = FakeTokenStorage();
    final repository = AuthRepository(api: api, storage: storage);
    final session = await repository.login('0812345678', 'password');
    expect(session.user.role, 'DRIVER');
    expect(storage.writeCount, 1);
    expect(storage.tokens?.accessToken, 'test-access-token');
    expect(storage.tokens?.refreshToken, 'test-refresh-token');
  });

  test('restore reads tokens and verifies them with auth me', () async {
    final api = FakeAuthApi();
    final storage = FakeTokenStorage(
      const AuthTokens(accessToken: 'saved', refreshToken: 'refresh'),
    );
    final repository = AuthRepository(api: api, storage: storage);
    final session = await repository.restoreSession();
    expect(session?.user.role, 'DRIVER');
    expect(storage.readCount, 1);
    expect(api.meCount, 1);
  });

  test('unauthorized restore clears expired tokens', () async {
    final api = FakeAuthApi()
      ..meError = const ApiException(ApiFailureKind.unauthorized);
    final storage = FakeTokenStorage(const AuthTokens(accessToken: 'expired'));
    final repository = AuthRepository(api: api, storage: storage);
    expect(await repository.restoreSession(), isNull);
    expect(storage.clearCount, 1);
  });

  test('network restore failure preserves tokens', () async {
    final api = FakeAuthApi()
      ..meError = const ApiException(ApiFailureKind.unavailable);
    final storage = FakeTokenStorage(const AuthTokens(accessToken: 'saved'));
    final repository = AuthRepository(api: api, storage: storage);
    await expectLater(
      repository.restoreSession(),
      throwsA(isA<ApiException>()),
    );
    expect(storage.clearCount, 0);
    expect(storage.tokens?.accessToken, 'saved');
  });

  test('logout clears local tokens even when server logout fails', () async {
    final api = FakeAuthApi()
      ..logoutError = const ApiException(ApiFailureKind.unavailable);
    final storage = FakeTokenStorage(
      const AuthTokens(accessToken: 'saved', refreshToken: 'refresh'),
    );
    final repository = AuthRepository(api: api, storage: storage);
    await repository.logout();
    expect(api.logoutCount, 1);
    expect(storage.clearCount, 1);
    expect(storage.tokens, isNull);
  });
}

import 'dart:async';

import 'package:tride_driver/core/network/api_exception.dart';
import 'package:tride_driver/core/storage/secure_token_storage.dart';
import 'package:tride_driver/features/auth/data/auth_api.dart';
import 'package:tride_driver/features/auth/data/auth_models.dart';

DriverUser driverUser({int id = 7, String? name = 'Somchai'}) =>
    DriverUser(id: id, role: 'DRIVER', isActive: true, name: name);

AuthSession driverSession() => AuthSession(
  user: driverUser(),
  accessToken: 'test-access-token',
  refreshToken: 'test-refresh-token',
  expiresIn: 3600,
);

class FakeTokenStorage implements TokenStorage {
  FakeTokenStorage([this.tokens]);

  AuthTokens? tokens;
  int readCount = 0;
  int writeCount = 0;
  int clearCount = 0;

  @override
  Future<void> clear() async {
    clearCount++;
    tokens = null;
  }

  @override
  Future<AuthTokens?> read() async {
    readCount++;
    return tokens;
  }

  @override
  Future<void> write(AuthTokens value) async {
    writeCount++;
    tokens = value;
  }
}

class FakeAuthApi implements AuthDataSource {
  AuthSession loginResult = driverSession();
  DriverUser meResult = driverUser();
  ApiException? loginError;
  ApiException? meError;
  ApiException? logoutError;
  Completer<AuthSession>? loginCompleter;
  int loginCount = 0;
  int meCount = 0;
  int logoutCount = 0;

  @override
  Future<DriverUser> getMe(String accessToken) async {
    meCount++;
    if (meError case final error?) throw error;
    return meResult;
  }

  @override
  Future<AuthSession> login(String loginId, String password) async {
    loginCount++;
    if (loginCompleter case final completer?) return completer.future;
    if (loginError case final error?) throw error;
    return loginResult;
  }

  @override
  Future<void> logout(AuthTokens tokens) async {
    logoutCount++;
    if (logoutError case final error?) throw error;
  }
}

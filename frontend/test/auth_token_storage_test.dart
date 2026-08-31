import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/token_storage.dart';
import 'package:frontend/features/auth/models/auth_session.dart';
import 'package:frontend/features/auth/models/auth_user.dart';
import 'package:frontend/features/auth/services/auth_token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('saveSession persists and reloads customer auth tokens', () async {
    final storage = AuthTokenStorage();
    const session = AuthSession(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      user: AuthUser(
        id: 1,
        role: 'CUSTOMER',
        email: 'customer@example.com',
        name: 'Customer',
      ),
    );

    await storage.saveSession(session);
    final loaded = await storage.loadSession();

    expect(loaded, isNotNull);
    expect(loaded!.accessToken, 'access-token');
    expect(loaded.refreshToken, 'refresh-token');
    expect(loaded.user.email, 'customer@example.com');

    final prefs = await SharedPreferences.getInstance();
    expect(
      jsonDecode(prefs.getString(AuthTokenStorage.userJsonKey)!),
      session.user.toJson(),
    );
  });

  test('clear removes stored customer auth session', () async {
    final storage = AuthTokenStorage();
    await storage.saveSession(
      const AuthSession(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        user: AuthUser(id: 1, role: 'CUSTOMER', email: 'customer@example.com'),
      ),
    );

    await storage.clear();
    final loaded = await storage.loadSession();

    expect(loaded, isNull);
  });

  test('write updates access token for refresh without clearing user json', () async {
    final storage = AuthTokenStorage();
    await storage.saveSession(
      const AuthSession(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        user: AuthUser(id: 1, role: 'CUSTOMER', email: 'customer@example.com'),
      ),
    );

    await storage.write(
      const AuthTokens(
        accessToken: 'fresh-access',
        refreshToken: 'refresh-token',
      ),
    );

    final loaded = await storage.loadSession();
    expect(loaded, isNotNull);
    expect(loaded!.accessToken, 'fresh-access');
    expect(loaded.user.email, 'customer@example.com');
  });
}

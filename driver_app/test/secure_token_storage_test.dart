import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tride_driver/core/storage/secure_token_storage.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('writes and reads access and refresh tokens securely', () async {
    final storage = SecureTokenStorage();
    await storage.write(
      const AuthTokens(accessToken: 'access', refreshToken: 'refresh'),
    );
    final tokens = await storage.read();
    expect(tokens?.accessToken, 'access');
    expect(tokens?.refreshToken, 'refresh');
  });

  test('clear removes all stored authentication tokens', () async {
    final storage = SecureTokenStorage();
    await storage.write(
      const AuthTokens(accessToken: 'access', refreshToken: 'refresh'),
    );
    await storage.clear();
    expect(await storage.read(), isNull);
  });
}

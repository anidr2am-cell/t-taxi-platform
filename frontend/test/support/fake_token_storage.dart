import 'package:frontend/core/network/token_storage.dart';

class FakeTokenStorage implements TokenStorage {
  FakeTokenStorage(this.tokens);

  AuthTokens? tokens;

  @override
  Future<void> clear() async {
    tokens = null;
  }

  @override
  Future<AuthTokens?> read() async => tokens;

  @override
  Future<void> write(AuthTokens value) async {
    tokens = value;
  }
}

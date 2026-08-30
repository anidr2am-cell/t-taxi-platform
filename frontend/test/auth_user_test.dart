import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/models/auth_user.dart';

void main() {
  test('AuthUser.fromJson parses authProvider and linkedProviders', () {
    final user = AuthUser.fromJson({
      'id': 42,
      'role': 'CUSTOMER',
      'email': 'user@example.com',
      'name': 'User',
      'authProvider': 'GOOGLE',
      'linkedProviders': ['GOOGLE', 'LINE'],
    });

    expect(user.authProvider, 'GOOGLE');
    expect(user.linkedProviders, ['GOOGLE', 'LINE']);
  });

  test('AuthUser.toJson includes provider fields when present', () {
    const user = AuthUser(
      id: 1,
      role: 'CUSTOMER',
      email: 'user@example.com',
      authProvider: 'KAKAO',
      linkedProviders: ['KAKAO'],
    );

    expect(user.toJson()['authProvider'], 'KAKAO');
    expect(user.toJson()['linkedProviders'], ['KAKAO']);
  });
}

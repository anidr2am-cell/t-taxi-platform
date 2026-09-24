/// API `user` payload for social OAuth callback widget tests.
Map<String, dynamic> oauthCallbackTestUser({
  required int id,
  required String email,
  required String name,
  String? phone,
  String locale = 'ko',
}) {
  return {
    'id': id,
    'email': email,
    'role': 'CUSTOMER',
    'name': name,
    'phone': phone,
    'locale': locale,
    'isActive': true,
  };
}

/// User with a valid phone for booking-complete / home return scenarios.
Map<String, dynamic> oauthCallbackTestUserWithPhone({
  required int id,
  required String email,
  required String name,
  String locale = 'ko',
}) {
  return oauthCallbackTestUser(
    id: id,
    email: email,
    name: name,
    phone: '+66812345678',
    locale: locale,
  );
}

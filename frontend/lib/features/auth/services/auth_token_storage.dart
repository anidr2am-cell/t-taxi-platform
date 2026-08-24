import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_session.dart';
import '../models/auth_user.dart';

class AuthTokenStorage {
  static const accessTokenKey = 'customer_access_token';
  static const refreshTokenKey = 'customer_refresh_token';
  static const userJsonKey = 'customer_user_json';

  Future<AuthSession?> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString(accessTokenKey);
    final refreshToken = prefs.getString(refreshTokenKey);
    final userRaw = prefs.getString(userJsonKey);
    if (accessToken == null ||
        accessToken.isEmpty ||
        refreshToken == null ||
        refreshToken.isEmpty ||
        userRaw == null ||
        userRaw.isEmpty) {
      return null;
    }

    try {
      final user = AuthUser.fromJson(
        Map<String, dynamic>.from(jsonDecode(userRaw) as Map),
      );
      return AuthSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
        user: user,
      );
    } catch (_) {
      await clear();
      return null;
    }
  }

  Future<void> saveSession(AuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(accessTokenKey, session.accessToken);
    await prefs.setString(refreshTokenKey, session.refreshToken);
    await prefs.setString(userJsonKey, jsonEncode(session.user.toJson()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(accessTokenKey);
    await prefs.remove(refreshTokenKey);
    await prefs.remove(userJsonKey);
  }
}

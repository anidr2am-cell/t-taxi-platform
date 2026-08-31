import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/token_storage.dart';
import '../models/auth_session.dart';
import '../models/auth_user.dart';

class AuthTokenStorage implements TokenStorage {
  static const accessTokenKey = 'customer_access_token';
  static const refreshTokenKey = 'customer_refresh_token';
  static const userJsonKey = 'customer_user_json';
  static const accessTokenExpiresAtKey = 'customer_access_token_expires_at';

  @override
  Future<AuthTokens?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString(accessTokenKey);
    final refreshToken = prefs.getString(refreshTokenKey);
    final hasAccess = accessToken != null && accessToken.isNotEmpty;
    final hasRefresh = refreshToken != null && refreshToken.isNotEmpty;
    if (!hasAccess && !hasRefresh) {
      return null;
    }
    return AuthTokens(
      accessToken: hasAccess ? accessToken : '',
      refreshToken: hasRefresh ? refreshToken : null,
      accessTokenExpiresAt: _parseExpiresAt(
        prefs.getString(accessTokenExpiresAtKey),
      ),
    );
  }

  Future<String?> readRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString(refreshTokenKey)?.trim();
    if (refreshToken == null || refreshToken.isEmpty) {
      return null;
    }
    return refreshToken;
  }

  Future<String?> readAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString(accessTokenKey)?.trim();
    if (accessToken == null || accessToken.isEmpty) {
      return null;
    }
    return accessToken;
  }

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
        expiresIn: _expiresInSeconds(
          _parseExpiresAt(prefs.getString(accessTokenExpiresAtKey)),
        ),
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
    final expiresAt = session.expiresIn == null
        ? null
        : DateTime.now().toUtc().add(Duration(seconds: session.expiresIn!));
    await _writeExpiresAt(prefs, expiresAt);
  }

  @override
  Future<void> write(AuthTokens tokens) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(accessTokenKey, tokens.accessToken);
    final refreshToken = tokens.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      await prefs.remove(refreshTokenKey);
    } else {
      await prefs.setString(refreshTokenKey, refreshToken);
    }
    await _writeExpiresAt(prefs, tokens.accessTokenExpiresAt);
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(accessTokenKey);
    await prefs.remove(refreshTokenKey);
    await prefs.remove(userJsonKey);
    await prefs.remove(accessTokenExpiresAtKey);
  }

  DateTime? _parseExpiresAt(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  int? _expiresInSeconds(DateTime? expiresAt) {
    if (expiresAt == null) return null;
    final seconds = expiresAt.difference(DateTime.now().toUtc()).inSeconds;
    return seconds > 0 ? seconds : null;
  }

  Future<void> _writeExpiresAt(
    SharedPreferences prefs,
    DateTime? expiresAt,
  ) async {
    if (expiresAt == null) {
      await prefs.remove(accessTokenExpiresAtKey);
      return;
    }
    await prefs.setString(
      accessTokenExpiresAtKey,
      expiresAt.toUtc().toIso8601String(),
    );
  }
}

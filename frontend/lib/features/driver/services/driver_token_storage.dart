import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/token_storage.dart';

class DriverTokenStorage implements TokenStorage {
  DriverTokenStorage();

  static const accessTokenKey = 'driver_access_token';
  static const refreshTokenKey = 'driver_refresh_token';
  static const accessTokenExpiresAtKey = 'driver_access_token_expires_at';
  static const displayNameKey = 'driver_display_name';

  @override
  Future<AuthTokens?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString(accessTokenKey);
    if (accessToken == null || accessToken.isEmpty) {
      return null;
    }
    final expiresAtRaw = prefs.getString(accessTokenExpiresAtKey);
    return AuthTokens(
      accessToken: accessToken,
      refreshToken: prefs.getString(refreshTokenKey),
      accessTokenExpiresAt: _parseExpiresAt(expiresAtRaw),
    );
  }

  Future<String?> readAccessToken() async {
    final tokens = await read();
    return tokens?.accessToken;
  }

  Future<String?> readDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(displayNameKey);
  }

  Future<void> saveLoginSession({
    required String accessToken,
    String? refreshToken,
    int? expiresIn,
    String? displayName,
  }) async {
    final expiresAt = expiresIn != null
        ? DateTime.now().toUtc().add(Duration(seconds: expiresIn))
        : null;
    await write(
      AuthTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
        accessTokenExpiresAt: expiresAt,
      ),
    );
    if (displayName != null && displayName.trim().isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(displayNameKey, displayName.trim());
    }
  }

  Future<void> saveDisplayName(String displayName) async {
    if (displayName.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(displayNameKey, displayName.trim());
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
    final expiresAt = _formatExpiresAt(tokens.accessTokenExpiresAt);
    if (expiresAt == null || expiresAt.isEmpty) {
      await prefs.remove(accessTokenExpiresAtKey);
    } else {
      await prefs.setString(accessTokenExpiresAtKey, expiresAt);
    }
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(accessTokenKey);
    await prefs.remove(refreshTokenKey);
    await prefs.remove(accessTokenExpiresAtKey);
    await prefs.remove(displayNameKey);
  }

  DateTime? _parseExpiresAt(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  String? _formatExpiresAt(DateTime? value) {
    if (value == null) return null;
    return value.toUtc().toIso8601String();
  }
}

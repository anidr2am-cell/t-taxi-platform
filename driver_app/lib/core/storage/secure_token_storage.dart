import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthTokens {
  const AuthTokens({required this.accessToken, this.refreshToken});

  final String accessToken;
  final String? refreshToken;
}

class DriverApplicationStoredInfo {
  const DriverApplicationStoredInfo({
    required this.applicationNumber,
    required this.statusToken,
    required this.submittedAt,
  });

  final String applicationNumber;
  final String statusToken;
  final String submittedAt;
}

abstract interface class TokenStorage {
  Future<AuthTokens?> read();
  Future<void> write(AuthTokens tokens);
  Future<void> clear();
  Future<int?> readNotificationDeviceId();
  Future<void> writeNotificationDeviceId(int deviceId);
  Future<void> clearNotificationDeviceId();
  Future<DriverApplicationStoredInfo?> readDriverApplicationInfo();
  Future<void> writeDriverApplicationInfo({
    required String applicationNumber,
    required String statusToken,
    required String submittedAt,
  });
  Future<void> clearDriverApplicationInfo();
}

class SecureTokenStorage implements TokenStorage {
  SecureTokenStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const accessTokenKey = 'auth_access_token';
  static const refreshTokenKey = 'auth_refresh_token';
  static const notificationDeviceIdKey = 'notification_device_id';
  static const driverApplicationNumberKey = 'driver_application_number';
  static const driverApplicationStatusTokenKey =
      'driver_application_status_token';
  static const driverApplicationSubmittedAtKey =
      'driver_application_submitted_at';

  final FlutterSecureStorage _storage;

  @override
  Future<AuthTokens?> read() async {
    final accessToken = await _storage.read(key: accessTokenKey);
    if (accessToken == null || accessToken.isEmpty) return null;
    return AuthTokens(
      accessToken: accessToken,
      refreshToken: await _storage.read(key: refreshTokenKey),
    );
  }

  @override
  Future<void> write(AuthTokens tokens) async {
    await _storage.write(key: accessTokenKey, value: tokens.accessToken);
    final refreshToken = tokens.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      await _storage.delete(key: refreshTokenKey);
    } else {
      await _storage.write(key: refreshTokenKey, value: refreshToken);
    }
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: accessTokenKey);
    await _storage.delete(key: refreshTokenKey);
    await clearNotificationDeviceId();
  }

  @override
  Future<int?> readNotificationDeviceId() async {
    final raw = await _storage.read(key: notificationDeviceIdKey);
    if (raw == null || raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  @override
  Future<void> writeNotificationDeviceId(int deviceId) async {
    if (deviceId <= 0) {
      await clearNotificationDeviceId();
      return;
    }
    await _storage.write(
      key: notificationDeviceIdKey,
      value: deviceId.toString(),
    );
  }

  @override
  Future<void> clearNotificationDeviceId() async {
    await _storage.delete(key: notificationDeviceIdKey);
  }

  @override
  Future<DriverApplicationStoredInfo?> readDriverApplicationInfo() async {
    final applicationNumber = await _storage.read(
      key: driverApplicationNumberKey,
    );
    if (applicationNumber == null || applicationNumber.isEmpty) return null;
    return DriverApplicationStoredInfo(
      applicationNumber: applicationNumber,
      statusToken:
          await _storage.read(key: driverApplicationStatusTokenKey) ?? '',
      submittedAt: await _storage.read(key: driverApplicationSubmittedAtKey) ??
          '',
    );
  }

  @override
  Future<void> writeDriverApplicationInfo({
    required String applicationNumber,
    required String statusToken,
    required String submittedAt,
  }) async {
    await _storage.write(
      key: driverApplicationNumberKey,
      value: applicationNumber.trim(),
    );
    await _storage.write(
      key: driverApplicationStatusTokenKey,
      value: statusToken.trim(),
    );
    await _storage.write(
      key: driverApplicationSubmittedAtKey,
      value: submittedAt.trim(),
    );
  }

  @override
  Future<void> clearDriverApplicationInfo() async {
    await _storage.delete(key: driverApplicationNumberKey);
    await _storage.delete(key: driverApplicationStatusTokenKey);
    await _storage.delete(key: driverApplicationSubmittedAtKey);
  }
}

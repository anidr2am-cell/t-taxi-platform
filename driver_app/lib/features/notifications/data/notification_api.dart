import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/storage/secure_token_storage.dart';

abstract interface class NotificationDataSource {
  Future<RegisteredNotificationDevice> registerDevice({
    required String token,
    String? deviceName,
    String? appVersion,
  });

  Future<void> deactivateDevice(int deviceId);
}

class RegisteredNotificationDevice {
  const RegisteredNotificationDevice({
    required this.deviceId,
    required this.platform,
  });

  final int deviceId;
  final String platform;

  factory RegisteredNotificationDevice.fromJson(Map<String, dynamic> json) {
    final deviceId = json['deviceId'];
    if (deviceId is! num) {
      throw const ApiException(ApiFailureKind.invalidResponse);
    }
    return RegisteredNotificationDevice(
      deviceId: deviceId.toInt(),
      platform: json['platform'] as String? ?? 'ANDROID',
    );
  }
}

class NotificationApi implements NotificationDataSource {
  const NotificationApi({
    required ApiClient client,
    required TokenStorage storage,
  }) : _client = client,
       _storage = storage;

  final ApiClient _client;
  final TokenStorage _storage;

  @override
  Future<RegisteredNotificationDevice> registerDevice({
    required String token,
    String? deviceName,
    String? appVersion,
  }) async {
    final body = <String, dynamic>{
      'token': token,
      // TODO(iOS): 서버가 'IOS' 값을 지원하는지 backend 확인 필요.
      // 확인 전까지 하드코딩 유지
      'platform': 'ANDROID',
      if (deviceName != null && deviceName.isNotEmpty) 'deviceName': deviceName,
      if (appVersion != null && appVersion.isNotEmpty) 'appVersion': appVersion,
    };
    final envelope = await _client.postJson(
      '/api/v1/notifications/devices',
      bearerToken: await _token(),
      body: body,
    );
    return RegisteredNotificationDevice.fromJson(_data(envelope));
  }

  @override
  Future<void> deactivateDevice(int deviceId) async {
    if (deviceId <= 0) {
      throw const ApiException(ApiFailureKind.validation);
    }
    await _client.deleteJson(
      '/api/v1/notifications/devices/$deviceId',
      bearerToken: await _token(),
    );
  }

  Map<String, dynamic> _data(Map<String, dynamic> envelope) {
    final data = envelope['data'];
    if (data is! Map) throw const ApiException(ApiFailureKind.invalidResponse);
    return Map<String, dynamic>.from(data);
  }

  Future<String> _token() async {
    final token = (await _storage.read())?.accessToken;
    if (token == null || token.isEmpty) {
      throw const ApiException(ApiFailureKind.unauthorized);
    }
    return token;
  }
}

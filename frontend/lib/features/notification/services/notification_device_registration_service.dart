import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_config.dart';

enum NotificationDeviceRegistrationStatus {
  registered,
  permissionDenied,
  unsupported,
  configMissing,
  failed,
}

class NotificationDeviceRegistrationResult {
  const NotificationDeviceRegistrationResult(this.status, {this.message});

  final NotificationDeviceRegistrationStatus status;
  final String? message;

  bool get registered => status == NotificationDeviceRegistrationStatus.registered;
}

abstract class PushMessagingClient {
  Future<NotificationDeviceRegistrationStatus?> initialize();
  Future<NotificationSettings> requestPermission();
  Future<String?> getToken();
  Stream<String> get onTokenRefresh;
}

class FirebasePushMessagingClient implements PushMessagingClient {
  FirebasePushMessagingClient();

  FirebaseMessaging? _messaging;

  @override
  Future<NotificationDeviceRegistrationStatus?> initialize() async {
    if (!kIsWeb) return NotificationDeviceRegistrationStatus.unsupported;
    if (!AppConfig.hasFirebaseWebConfig) {
      return NotificationDeviceRegistrationStatus.configMissing;
    }
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: AppConfig.firebaseApiKey,
          appId: AppConfig.firebaseAppId,
          messagingSenderId: AppConfig.firebaseMessagingSenderId,
          projectId: AppConfig.firebaseProjectId,
          authDomain:
              AppConfig.firebaseAuthDomain.isEmpty ? null : AppConfig.firebaseAuthDomain,
          storageBucket:
              AppConfig.firebaseStorageBucket.isEmpty ? null : AppConfig.firebaseStorageBucket,
        ),
      );
    }
    _messaging = FirebaseMessaging.instance;
    return null;
  }

  @override
  Future<NotificationSettings> requestPermission() {
    return (_messaging ?? FirebaseMessaging.instance).requestPermission();
  }

  @override
  Future<String?> getToken() {
    return (_messaging ?? FirebaseMessaging.instance).getToken(
      vapidKey: AppConfig.firebaseVapidKey.isEmpty ? null : AppConfig.firebaseVapidKey,
    );
  }

  @override
  Stream<String> get onTokenRefresh => (_messaging ?? FirebaseMessaging.instance).onTokenRefresh;
}

class NotificationDeviceRegistrationService {
  NotificationDeviceRegistrationService({
    http.Client? client,
    PushMessagingClient? messagingClient,
    String? baseUrl,
  })  : _client = client ?? http.Client(),
        _messagingClient = messagingClient ?? FirebasePushMessagingClient(),
        _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _client;
  final PushMessagingClient _messagingClient;
  final String _baseUrl;
  StreamSubscription<String>? _refreshSubscription;

  static const _authDeviceIdKey = 'notification_device_id_authenticated';

  Future<NotificationDeviceRegistrationResult> enableAuthenticated({
    required Future<String?> Function() accessTokenLoader,
  }) async {
    return _enable((token) async {
      final accessToken = await accessTokenLoader();
      if (accessToken == null || accessToken.isEmpty) {
        return const NotificationDeviceRegistrationResult(
          NotificationDeviceRegistrationStatus.failed,
          message: 'Please log in again.',
        );
      }
      final deviceId = await _registerAuthenticated(token, accessToken);
      await _rememberDevice(_authDeviceIdKey, deviceId);
      _watchRefresh((newToken) => _registerAuthenticated(newToken, accessToken));
      return const NotificationDeviceRegistrationResult(
        NotificationDeviceRegistrationStatus.registered,
      );
    });
  }

  Future<NotificationDeviceRegistrationResult> enableGuest({
    required int? bookingId,
    required String? guestAccessToken,
  }) async {
    if (bookingId == null || guestAccessToken == null || guestAccessToken.isEmpty) {
      return const NotificationDeviceRegistrationResult(
        NotificationDeviceRegistrationStatus.failed,
        message: 'Notification registration is not available for this booking.',
      );
    }
    return _enable((token) async {
      final deviceId = await _registerGuest(token, bookingId, guestAccessToken);
      await _rememberDevice(_guestDeviceIdKey(bookingId), deviceId);
      _watchRefresh((newToken) => _registerGuest(newToken, bookingId, guestAccessToken));
      return const NotificationDeviceRegistrationResult(
        NotificationDeviceRegistrationStatus.registered,
      );
    });
  }

  Future<NotificationDeviceRegistrationResult> _enable(
    Future<NotificationDeviceRegistrationResult> Function(String token) register,
  ) async {
    try {
      final initStatus = await _messagingClient.initialize();
      if (initStatus != null) {
        return NotificationDeviceRegistrationResult(initStatus);
      }
      final settings = await _messagingClient.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return const NotificationDeviceRegistrationResult(
          NotificationDeviceRegistrationStatus.permissionDenied,
        );
      }
      final token = await _messagingClient.getToken();
      if (token == null || token.isEmpty) {
        return const NotificationDeviceRegistrationResult(
          NotificationDeviceRegistrationStatus.failed,
          message: 'Unable to get a notification token.',
        );
      }
      return await register(token);
    } catch (err) {
      return NotificationDeviceRegistrationResult(
        NotificationDeviceRegistrationStatus.failed,
        message: err.toString(),
      );
    }
  }

  Future<int> _registerAuthenticated(String token, String accessToken) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/api/v1/notifications/devices'),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode(_body(token)),
    );
    return _parseDeviceResponse(response);
  }

  Future<int> _registerGuest(String token, int bookingId, String guestAccessToken) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/api/v1/public/bookings/$bookingId/notification-devices'),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'X-Guest-Access-Token': guestAccessToken,
      },
      body: jsonEncode(_body(token)),
    );
    return _parseDeviceResponse(response);
  }

  Map<String, dynamic> _body(String token) => {
        'token': token,
        'platform': kIsWeb ? 'WEB' : defaultTargetPlatform.name.toUpperCase(),
        'deviceName': 'TTaxi Web',
        'appVersion': '1.0.0',
      };

  int _parseDeviceResponse(http.Response response) {
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw decoded['message'] as String? ?? 'Notification registration failed';
    }
    final data = Map<String, dynamic>.from(decoded['data'] as Map);
    return data['deviceId'] as int? ?? 0;
  }

  void _watchRefresh(Future<int> Function(String token) register) {
    _refreshSubscription?.cancel();
    _refreshSubscription = _messagingClient.onTokenRefresh.listen((token) {
      unawaited(register(token));
    });
  }

  Future<void> deactivateAuthenticated({
    required Future<String?> Function() accessTokenLoader,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getInt(_authDeviceIdKey);
    final accessToken = await accessTokenLoader();
    if (deviceId == null || accessToken == null || accessToken.isEmpty) return;
    await _client.delete(
      Uri.parse('$_baseUrl/api/v1/notifications/devices/$deviceId'),
      headers: {'Authorization': 'Bearer $accessToken', 'Accept': 'application/json'},
    );
    await prefs.remove(_authDeviceIdKey);
  }

  Future<void> deactivateGuest({
    required int bookingId,
    required String guestAccessToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _guestDeviceIdKey(bookingId);
    final deviceId = prefs.getInt(key);
    if (deviceId == null) return;
    await _client.delete(
      Uri.parse('$_baseUrl/api/v1/public/bookings/$bookingId/notification-devices/$deviceId'),
      headers: {'X-Guest-Access-Token': guestAccessToken, 'Accept': 'application/json'},
    );
    await prefs.remove(key);
  }

  Future<void> _rememberDevice(String key, int deviceId) async {
    if (deviceId <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, deviceId);
  }

  static String _guestDeviceIdKey(int bookingId) => 'notification_device_id_guest_$bookingId';
}

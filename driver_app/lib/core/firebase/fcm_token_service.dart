import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../features/notifications/data/notification_api.dart';
import '../storage/secure_token_storage.dart';

abstract interface class FcmMessagingClient {
  Future<void> requestPermission();
  Future<String?> getToken();
  Stream<String> get onTokenRefresh;
}

class FirebaseFcmMessagingClient implements FcmMessagingClient {
  FirebaseFcmMessagingClient([FirebaseMessaging? messaging])
    : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;

  @override
  Future<void> requestPermission() async {
    await _messaging.requestPermission();
  }

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;
}

typedef PackageInfoProvider = Future<PackageInfo> Function();

class FcmTokenService {
  FcmTokenService({
    required FcmMessagingClient messaging,
    required NotificationDataSource notificationApi,
    required TokenStorage storage,
    PackageInfoProvider? packageInfoProvider,
    Duration registrationRetryCooldown = const Duration(minutes: 5),
  }) : _messaging = messaging,
       _notificationApi = notificationApi,
       _storage = storage,
       _packageInfoProvider =
           packageInfoProvider ?? PackageInfo.fromPlatform,
       _registrationRetryCooldown = registrationRetryCooldown;

  final FcmMessagingClient _messaging;
  final NotificationDataSource _notificationApi;
  final TokenStorage _storage;
  final PackageInfoProvider _packageInfoProvider;
  final Duration _registrationRetryCooldown;
  StreamSubscription<String>? _tokenRefreshSubscription;
  Future<void>? _registerInFlight;
  String? _lastRegisteredToken;
  DateTime? _lastRegistrationAttemptAt;

  Future<void> registerIfNeeded() {
    final active = _registerInFlight;
    if (active != null) return active;
    final operation = _registerIfNeeded();
    _registerInFlight = operation;
    return operation.whenComplete(() {
      if (identical(_registerInFlight, operation)) {
        _registerInFlight = null;
      }
    });
  }

  Future<void> _registerIfNeeded() async {
    if (await _storage.read() == null) return;

    _ensureTokenRefreshListener();

    try {
      await _messaging.requestPermission();
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) return;
      if (await _shouldSkipRegistration(token)) return;

      _lastRegistrationAttemptAt = DateTime.now();
      await _registerToken(token);
    } catch (error, stackTrace) {
      _logFailure('FCM token registration failed', error, stackTrace);
    }
  }

  Future<bool> _shouldSkipRegistration(String token) async {
    if (_lastRegisteredToken != token) return false;

    final deviceId = await _storage.readNotificationDeviceId();
    if (deviceId != null) return true;

    final lastAttempt = _lastRegistrationAttemptAt;
    if (lastAttempt == null) return false;
    return DateTime.now().difference(lastAttempt) < _registrationRetryCooldown;
  }

  void _ensureTokenRefreshListener() {
    if (_tokenRefreshSubscription != null) return;
    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen(
      (token) async {
        if (token.isEmpty) return;
        if (await _storage.read() == null) return;
        try {
          if (await _shouldSkipRegistration(token)) return;
          _lastRegistrationAttemptAt = DateTime.now();
          await _registerToken(token);
        } catch (error, stackTrace) {
          _logFailure('FCM token refresh registration failed', error, stackTrace);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _logFailure('FCM token refresh stream failed', error, stackTrace);
      },
    );
  }

  Future<void> _registerToken(String token) async {
    final packageInfo = await _packageInfoProvider();
    final appVersion = packageInfo.version.trim();
    final registered = await _notificationApi.registerDevice(
      token: token,
      appVersion: appVersion.isEmpty ? null : appVersion,
    );
    await _storage.writeNotificationDeviceId(registered.deviceId);
    _lastRegisteredToken = token;
  }

  Future<void> deactivateStoredDevice({required bool clearStoredId}) async {
    final deviceId = await _storage.readNotificationDeviceId();
    if (deviceId == null) return;
    try {
      await _notificationApi.deactivateDevice(deviceId);
    } catch (error, stackTrace) {
      _logFailure('FCM device deactivation failed', error, stackTrace);
    } finally {
      _lastRegisteredToken = null;
      _lastRegistrationAttemptAt = null;
      if (clearStoredId) {
        await _storage.clearNotificationDeviceId();
      }
    }
  }

  void dispose() {
    unawaited(_tokenRefreshSubscription?.cancel());
    _tokenRefreshSubscription = null;
  }

  void _logFailure(String message, Object error, StackTrace stackTrace) {
    if (kDebugMode) {
      debugPrint('$message: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}

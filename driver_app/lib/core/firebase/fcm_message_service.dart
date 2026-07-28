import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'fcm_navigation_service.dart';

typedef FcmTabNavigator = void Function(int tabIndex);

abstract interface class FcmMessageStreams {
  Stream<RemoteMessage> get onMessage;
  Stream<RemoteMessage> get onMessageOpenedApp;
  Future<RemoteMessage?> getInitialMessage();
}

class FirebaseFcmMessageStreams implements FcmMessageStreams {
  FirebaseFcmMessageStreams([FirebaseMessaging? messaging])
    : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;

  @override
  Stream<RemoteMessage> get onMessage => FirebaseMessaging.onMessage;

  @override
  Stream<RemoteMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp;

  @override
  Future<RemoteMessage?> getInitialMessage() =>
      _messaging.getInitialMessage();
}

class FcmMessageService {
  FcmMessageService({required FcmMessageStreams messaging})
    : _messaging = messaging;

  final FcmMessageStreams _messaging;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedAppSubscription;
  FcmTabNavigator? _navigateToTab;
  bool _listenersAttached = false;

  bool get listenersAttached => _listenersAttached;

  Future<void> attachShellNavigator(FcmTabNavigator navigateToTab) async {
    _navigateToTab = navigateToTab;
    if (_listenersAttached) return;

    try {
      _foregroundSubscription ??= _messaging.onMessage.listen(
        _handleForegroundMessage,
        onError: _logStreamError,
      );
      _openedAppSubscription ??= _messaging.onMessageOpenedApp.listen(
        _handleOpenedMessage,
        onError: _logStreamError,
      );
      _listenersAttached = true;

      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleOpenedMessage(initialMessage);
      }
    } catch (error, stackTrace) {
      _logFailure('FCM message listener setup failed', error, stackTrace);
    }
  }

  void detachShellNavigator() {
    _navigateToTab = null;
  }

  void dispose() {
    unawaited(_foregroundSubscription?.cancel());
    unawaited(_openedAppSubscription?.cancel());
    _foregroundSubscription = null;
    _openedAppSubscription = null;
    _navigateToTab = null;
    _listenersAttached = false;
  }

  void _handleForegroundMessage(RemoteMessage message) {
    if (shouldHandleSettlementApprovedInForeground(message.data)) {
      _handleOpenedMessage(message);
      return;
    }
    if (kDebugMode) {
      debugPrint(
        'FCM foreground message ignored: id=${message.messageId}, '
        'type=${message.data['notificationType']}',
      );
    }
  }

  void _handleOpenedMessage(RemoteMessage message) {
    try {
      final tabIndex = tabIndexForFcmData(message.data);
      if (tabIndex == null) return;
      _navigateToTab?.call(tabIndex);
    } catch (error, stackTrace) {
      _logFailure('FCM notification navigation failed', error, stackTrace);
    }
  }

  void _logStreamError(Object error, StackTrace stackTrace) {
    _logFailure('FCM message stream failed', error, stackTrace);
  }

  void _logFailure(String message, Object error, StackTrace stackTrace) {
    if (kDebugMode) {
      debugPrint('$message: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}

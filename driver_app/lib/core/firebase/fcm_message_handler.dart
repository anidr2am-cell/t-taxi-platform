import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'firebase_app_initializer.dart';

/// Handles FCM messages while the app is in background or terminated.
///
/// System notification UI is shown automatically when the payload includes a
/// `notification` block; this handler only logs for diagnostics.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await initializeFirebaseApp();
  if (kDebugMode) {
    debugPrint(
      'FCM background message received: id=${message.messageId}, '
      'type=${message.data['notificationType']}',
    );
  }
}

void registerFcmBackgroundHandler() {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return;
  }
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
}

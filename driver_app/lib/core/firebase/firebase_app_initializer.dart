import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Initializes Firebase once on supported native platforms.
///
/// Android uses [google-services.json] processed by the Gradle plugin.
/// Initialization is skipped on web/iOS in this phase and fails softly when
/// native Firebase config is unavailable (e.g. flutter test on a host VM).
Future<void> initializeFirebaseApp() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    // TODO(iOS): GoogleService-Info.plist 및 Push capability 설정 완료 후
    // iOS 분기 활성화 예정 (Mac 확보 후)
    return;
  }
  if (Firebase.apps.isNotEmpty) {
    return;
  }

  try {
    await Firebase.initializeApp();
  } on Object {
    // Allow local/tests to continue without native Firebase wiring.
  }
}

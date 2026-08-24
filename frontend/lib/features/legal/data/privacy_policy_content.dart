import 'package:flutter/services.dart' show rootBundle;

/// Loads the bundled privacy policy markdown (mirrors [docs/privacy_policy.md]).
abstract final class PrivacyPolicyContent {
  static const assetPath = 'assets/legal/privacy_policy.md';

  static Future<String> load() async {
    return rootBundle.loadString(assetPath);
  }
}

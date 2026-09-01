import 'app_config.dart';

/// GA4 measurement configuration (compile-time via `--dart-define`).
class Ga4Config {
  Ga4Config._();

  static const String measurementId = String.fromEnvironment(
    'GA4_MEASUREMENT_ID',
    defaultValue: '',
  );

  /// Send events only on production builds with an explicit measurement ID.
  static bool get isEnabled =>
      AppConfig.isProduction && measurementId.isNotEmpty;
}

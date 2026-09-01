import 'analytics_consent.dart';
import 'analytics_consent_stub.dart'
    if (dart.library.js_interop) 'analytics_consent_web.dart';

class AnalyticsConsentProvider {
  AnalyticsConsentProvider._();

  static final AnalyticsConsentService instance =
      AnalyticsConsentService(createAnalyticsConsentStorage());
}

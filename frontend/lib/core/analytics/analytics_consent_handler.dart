import 'analytics_consent.dart';
import 'analytics_consent_provider.dart';
import 'ga4_booking_analytics_sink.dart';
import 'marketing_attribution_provider.dart';

/// Applies analytics consent side-effects (GA4 + attribution storage).
void applyAnalyticsConsent(AnalyticsConsentService service, AnalyticsConsentStatus status) {
  switch (status) {
    case AnalyticsConsentStatus.granted:
      service.grant();
      MarketingAttributionProvider.onAnalyticsGranted();
      Ga4AnalyticsBootstrap.applyConsent(service);
    case AnalyticsConsentStatus.denied:
      service.deny();
      MarketingAttributionProvider.onAnalyticsDenied();
      Ga4AnalyticsBootstrap.applyConsent(service);
    case AnalyticsConsentStatus.unknown:
      break;
  }
}

AnalyticsConsentService get defaultAnalyticsConsentService =>
    AnalyticsConsentProvider.instance;

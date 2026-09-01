import 'analytics_consent_provider.dart';
import 'marketing_attribution.dart';
import 'marketing_attribution_stub.dart'
    if (dart.library.js_interop) 'marketing_attribution_web.dart';

/// Shared marketing attribution coordinator (web: localStorage when consented).
class MarketingAttributionProvider {
  MarketingAttributionProvider._();

  static final MarketingAttributionCoordinator coordinator =
      MarketingAttributionCoordinator(
        service: MarketingAttributionService(
          createMarketingAttributionStorage(),
        ),
      );

  static void captureLanding({
    required Uri uri,
    String? documentReferrer,
  }) {
    final consent = AnalyticsConsentProvider.instance;
    coordinator.captureLanding(
      uri: uri,
      documentReferrer: documentReferrer,
      analyticsGranted: consent.isGranted,
      analyticsDenied: consent.isDenied,
    );
  }

  static void onAnalyticsGranted() {
    coordinator.onAnalyticsGranted();
  }

  static void onAnalyticsDenied() {
    coordinator.onAnalyticsDenied();
  }

  /// Persisted attribution for booking API — only when analytics consent granted.
  static MarketingAttributionSnapshot? snapshotForBooking() {
    if (!AnalyticsConsentProvider.instance.isGranted) return null;
    final snapshot = coordinator.snapshotForBooking();
    if (snapshot == null || snapshot.isEmpty) return null;
    return snapshot;
  }

  static MarketingAttributionSnapshot? snapshotForAnalytics() {
    if (!AnalyticsConsentProvider.instance.isGranted) return null;
    return coordinator.snapshotForAnalytics();
  }
}

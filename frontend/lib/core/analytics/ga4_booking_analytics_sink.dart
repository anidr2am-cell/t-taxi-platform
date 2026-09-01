import '../../config/ga4_config.dart';
import '../../features/booking/services/booking_analytics.dart';
import 'analytics_consent.dart';
import 'ga4_bridge_stub.dart'
    if (dart.library.js_interop) 'ga4_bridge_web.dart';

/// Sends sanitized booking funnel events to GA4 via gtag (web only).
class Ga4BookingAnalyticsSink implements BookingAnalyticsSink {
  Ga4BookingAnalyticsSink({required this.consentService});

  final AnalyticsConsentService consentService;

  @override
  void emit(BookingAnalyticsEvent event) {
    if (!consentService.isGranted) return;

    final ga4Name = event.name;
    final params = _mapParams(event.properties);
    Ga4Bridge.event(ga4Name, params);

    if (event.name == 'booking_completed') {
      Ga4Bridge.event('generate_lead', {
        if (params['transaction_id'] != null)
          'transaction_id': params['transaction_id'],
        if (params['value'] != null) 'value': params['value'],
        'currency': params['currency'] ?? 'THB',
      });
    }
  }

  Map<String, Object?> _mapParams(Map<String, Object?> props) {
    final mapped = <String, Object?>{};
    for (final entry in props.entries) {
      mapped[_normalizeKey(entry.key)] = _normalizeValue(entry.value);
    }

    final bookingId = props['booking_id'];
    if (bookingId != null) {
      mapped['transaction_id'] = bookingId.toString();
    }
    if (props['total_price'] != null) {
      mapped['value'] = props['total_price'];
      mapped['currency'] = props['currency'] ?? 'THB';
    }

    return mapped;
  }

  String _normalizeKey(String key) {
    const blocked = {'booking_id', 'total_price'};
    if (blocked.contains(key)) {
      return key;
    }
    return key.replaceAllMapped(
      RegExp(r'[A-Z]'),
      (match) => '_${match.group(0)!.toLowerCase()}',
    );
  }

  Object? _normalizeValue(Object? value) {
    if (value is num || value is String || value is bool) return value;
    return value?.toString();
  }
}

class Ga4AnalyticsBootstrap {
  Ga4AnalyticsBootstrap._();

  static bool _bootstrapped = false;

  static void ensureInitialized({
    required AnalyticsConsentService consentService,
  }) {
    if (_bootstrapped || !Ga4Config.isEnabled) return;
    Ga4Bridge.init(Ga4Config.measurementId);
    Ga4Bridge.updateConsent(consentService.isGranted);
    _bootstrapped = true;
  }

  static void applyConsent(AnalyticsConsentService consentService) {
    if (!Ga4Config.isEnabled) return;
    Ga4Bridge.updateConsent(consentService.isGranted);
  }

  static void trackPage(String path, {String? title}) {
    if (!Ga4Config.isEnabled) return;
    Ga4Bridge.pageView(path, title: title);
  }
}

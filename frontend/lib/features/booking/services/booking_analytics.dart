import 'package:flutter/foundation.dart';

import '../../../config/ga4_config.dart';
import '../../../core/analytics/analytics_consent_provider.dart';
import '../../../core/analytics/ga4_booking_analytics_sink.dart';
import '../models/booking_wizard_steps.dart';
import '../models/service_type_option.dart';

/// A single analytics event emitted by the booking funnel.
class BookingAnalyticsEvent {
  const BookingAnalyticsEvent({
    required this.name,
    required this.properties,
  });

  final String name;
  final Map<String, Object?> properties;
}

/// Sink for analytics events. Replace with GA4/GTM adapter later.
abstract class BookingAnalyticsSink {
  void emit(BookingAnalyticsEvent event);
}

/// Discards events in production when no vendor SDK is configured.
class NoOpBookingAnalyticsSink implements BookingAnalyticsSink {
  const NoOpBookingAnalyticsSink();

  @override
  void emit(BookingAnalyticsEvent event) {}
}

/// Logs sanitized events in debug builds.
class DebugBookingAnalyticsSink implements BookingAnalyticsSink {
  @override
  void emit(BookingAnalyticsEvent event) {
    if (kDebugMode) {
      debugPrint('[BookingAnalytics] ${event.name} ${event.properties}');
    }
  }
}

class CompositeBookingAnalyticsSink implements BookingAnalyticsSink {
  CompositeBookingAnalyticsSink(this._sinks);

  final List<BookingAnalyticsSink> _sinks;

  @override
  void emit(BookingAnalyticsEvent event) {
    for (final sink in _sinks) {
      sink.emit(event);
    }
  }
}

/// In-memory sink for widget/unit tests.
class RecordingBookingAnalyticsSink implements BookingAnalyticsSink {
  final List<BookingAnalyticsEvent> events = [];

  @override
  void emit(BookingAnalyticsEvent event) {
    events.add(event);
  }

  void clear() => events.clear();

  List<BookingAnalyticsEvent> named(String name) =>
      events.where((event) => event.name == name).toList(growable: false);
}

/// Booking funnel analytics with PII filtering and dedupe guards.
class BookingAnalytics {
  BookingAnalytics(this._sink);

  static BookingAnalytics instance = BookingAnalytics(_buildDefaultSink());

  static BookingAnalyticsSink _buildDefaultSink() {
    if (kIsWeb && Ga4Config.isEnabled) {
      final ga4Sink = Ga4BookingAnalyticsSink(
        consentService: AnalyticsConsentProvider.instance,
      );
      if (kDebugMode) {
        return CompositeBookingAnalyticsSink([
          DebugBookingAnalyticsSink(),
          ga4Sink,
        ]);
      }
      return ga4Sink;
    }
    if (kDebugMode) {
      return DebugBookingAnalyticsSink();
    }
    return const NoOpBookingAnalyticsSink();
  }

  final BookingAnalyticsSink _sink;
  Map<String, Object?> _sessionContext = {};

  static const blockedPropertyKeys = {
    'customerName',
    'customer_name',
    'name',
    'phone',
    'customerPhone',
    'customer_phone',
    'countryCode',
    'country_code',
    'messengerId',
    'messenger_id',
    'messengerType',
    'flightNumber',
    'flight_number',
    'address',
    'placeId',
    'place_id',
    'latitude',
    'longitude',
    'lat',
    'lng',
    'additionalRequests',
    'guestAccessToken',
    'boardingQrToken',
    'idempotencyKey',
    'idempotency_key',
    'searchQuery',
    'query',
  };

  bool _bookingStarted = false;
  bool _submitAttemptTracked = false;
  final Set<String> _completedBookingIds = {};

  @visibleForTesting
  void resetSessionGuards() {
    _bookingStarted = false;
    _submitAttemptTracked = false;
    _completedBookingIds.clear();
    _sessionContext = {};
  }

  void setSessionContext(Map<String, Object?> context) {
    _sessionContext = Map<String, Object?>.from(context);
  }

  void mergeSessionContext(Map<String, Object?> context) {
    _sessionContext.addAll(context);
  }

  void track(String name, Map<String, Object?> properties) {
    final merged = <String, Object?>{
      ..._sessionContext,
      ...properties,
    };
    _sink.emit(
      BookingAnalyticsEvent(name: name, properties: _sanitize(merged)),
    );
  }

  Map<String, Object?> _sanitize(Map<String, Object?> properties) {
    final sanitized = <String, Object?>{};
    for (final entry in properties.entries) {
      if (blockedPropertyKeys.contains(entry.key)) continue;
      final value = entry.value;
      if (value == null) continue;
      sanitized[entry.key] = value;
    }
    return sanitized;
  }

  void trackBookingStarted({
    required String locale,
    required String deviceType,
  }) {
    if (_bookingStarted) return;
    _bookingStarted = true;
    track('booking_started', {
      'locale': locale,
      'device_type': deviceType,
    });
  }

  void trackStepViewed({required int stepNumber, required String stepName}) {
    track('booking_step_viewed', {
      'step_number': stepNumber,
      'step_name': stepName,
    });
  }

  void trackStepCompleted({
    required int stepNumber,
    required String stepName,
    String? routeType,
  }) {
    track('booking_step_completed', {
      'step_number': stepNumber,
      'step_name': stepName,
      if (routeType != null) 'route_type': routeType,
    });
  }

  void trackPlaceSearchFailed({
    required String placeType,
    required String errorCategory,
  }) {
    track('place_search_failed', {
      'place_type': placeType,
      'error_category': errorCategory,
    });
  }

  void trackVehicleSelected({
    required String vehicleType,
    num? quotedPrice,
  }) {
    track('vehicle_selected', {
      'vehicle_type': vehicleType,
      if (quotedPrice != null) 'quoted_price': quotedPrice.round(),
    });
  }

  void trackVehicleCapacityWarning({
    required String vehicleType,
    required String warningType,
  }) {
    track('vehicle_capacity_warning', {
      'vehicle_type': vehicleType,
      'warning_type': warningType,
    });
  }

  void trackBookingReviewViewed({
    String? vehicleType,
    String? routeType,
  }) {
    track('booking_review_viewed', {
      if (vehicleType != null) 'vehicle_type': vehicleType,
      if (routeType != null) 'route_type': routeType,
    });
  }

  void trackBookingSubmitted({
    String? vehicleType,
    String paymentMethod = 'PAY_DRIVER',
    String? bookingMode,
  }) {
    if (_submitAttemptTracked) return;
    _submitAttemptTracked = true;
    track('booking_submitted', {
      if (vehicleType != null) 'vehicle_type': vehicleType,
      'payment_method': paymentMethod,
      if (bookingMode != null) 'booking_mode': bookingMode,
    });
  }

  @Deprecated('Use trackBookingSubmitted')
  void trackBookingSubmitAttempted({
    String? vehicleType,
    String paymentMethod = 'PAY_DRIVER',
  }) {
    trackBookingSubmitted(
      vehicleType: vehicleType,
      paymentMethod: paymentMethod,
    );
  }

  void trackBookingCompleted({
    required String bookingId,
    String? vehicleType,
    num? totalPrice,
  }) {
    if (_completedBookingIds.contains(bookingId)) return;
    _completedBookingIds.add(bookingId);
    track('booking_completed', {
      'booking_id': bookingId,
      if (vehicleType != null) 'vehicle_type': vehicleType,
      if (totalPrice != null) 'total_price': totalPrice.round(),
      'currency': 'THB',
    });
  }

  void trackBookingCreated({
    required String bookingId,
    String? vehicleType,
    num? totalPrice,
    bool isUrgent = false,
  }) {
    track('booking_created', {
      'booking_id': bookingId,
      if (vehicleType != null) 'vehicle_type': vehicleType,
      if (totalPrice != null) 'total_price': totalPrice.round(),
      'is_urgent': isUrgent,
    });
  }

  void trackContactConnectViewed({
    required String bookingId,
    String? contactStatus,
  }) {
    track('contact_connect_viewed', {
      'booking_id': bookingId,
      if (contactStatus != null) 'contact_status': contactStatus,
    });
  }

  void trackContactConnectStarted({
    required String bookingId,
    required String channel,
  }) {
    track('contact_connect_started', {
      'booking_id': bookingId,
      'channel': channel,
    });
  }

  void trackContactConfirmRequested({
    required String bookingId,
    String? channel,
  }) {
    track('contact_confirm_requested', {
      'booking_id': bookingId,
      if (channel != null) 'channel': channel,
    });
  }

  void trackContactConnectSucceeded({required String bookingId}) {
    track('contact_connect_succeeded', {
      'booking_id': bookingId,
    });
  }

  void trackBookingFullyCompleted({
    required String bookingId,
    String? vehicleType,
    num? totalPrice,
    bool isUrgent = false,
  }) {
    track('booking_fully_completed', {
      'booking_id': bookingId,
      if (vehicleType != null) 'vehicle_type': vehicleType,
      if (totalPrice != null) 'total_price': totalPrice.round(),
      'is_urgent': isUrgent,
    });
  }

  void trackBookingFailed({
    required String stepName,
    required String errorCategory,
  }) {
    track('booking_failed', {
      'step_name': stepName,
      'error_category': errorCategory,
    });
    _submitAttemptTracked = false;
  }

  void trackSupportClicked({
    required String stepName,
    required String channel,
  }) {
    track('support_clicked', {
      'step_name': stepName,
      'channel': channel,
    });
  }

  static String stepNameFor(int step) => BookingWizardSteps.analyticsName(step);

  static String? routeTypeFor(BookingServiceType? serviceType) =>
      serviceType?.apiCode;

  static String deviceTypeForWidth(double width) =>
      width >= 720 ? 'desktop' : 'mobile';

  static String errorCategoryFor(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('socket') ||
        message.contains('network') ||
        message.contains('timeout') ||
        message.contains('connection')) {
      return 'network';
    }
    if (message.contains('not_found') || message.contains('route not found')) {
      return 'not_found';
    }
    if (message.contains('validation')) {
      return 'validation';
    }
    return 'api_error';
  }

  static String placeErrorCategory(Object error, {required bool noResults}) {
    if (noResults) return 'no_results';
    return errorCategoryFor(error);
  }
}

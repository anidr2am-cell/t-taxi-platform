import '../../booking/models/location_option.dart';
import '../../booking/models/service_type_option.dart';

class LandingBookingDraft {
  const LandingBookingDraft({
    this.serviceType,
    this.origin,
    this.destination,
  });

  final BookingServiceType? serviceType;
  final LocationOption? origin;
  final LocationOption? destination;

  bool get isRouteComplete =>
      serviceType != null && origin != null && destination != null;

  LandingBookingDraft copyWith({
    BookingServiceType? serviceType,
    LocationOption? origin,
    LocationOption? destination,
    bool clearOrigin = false,
    bool clearDestination = false,
  }) {
    return LandingBookingDraft(
      serviceType: serviceType ?? this.serviceType,
      origin: clearOrigin ? null : (origin ?? this.origin),
      destination: clearDestination ? null : (destination ?? this.destination),
    );
  }
}

import '../models/booking_wizard_route_args.dart';
import '../models/location_option.dart';
import 'booking_entry_session.dart';
import '../models/booking_wizard_steps.dart';
import '../models/service_type_option.dart';

/// Parses public booking-entry links. Future `from` and `to` parameters can be
/// added here without coupling external landing links to the booking UI.
abstract final class BookingEntryQuery {
  static BookingWizardRouteArgs? parse(Uri uri) {
    if (uri.path != '/booking') return null;
    final service = BookingServiceTypeX.fromApiCode(
      uri.queryParameters['service'],
    );
    if (service == null) return null;
    final entry = landingRouteEntry(uri);
    if (entry != null) {
      try {
        final origin = LocationOption.fromJson(
          Map<String, dynamic>.from(entry['origin'] as Map),
        );
        final destination = LocationOption.fromJson(
          Map<String, dynamic>.from(entry['destination'] as Map),
        );
        if (origin.hasCoordinates && destination.hasCoordinates) {
          return BookingWizardRouteArgs(
            serviceType: service,
            origin: origin,
            destination: destination,
            initialStep: BookingWizardSteps.route,
          );
        }
      } catch (_) {
        /* Invalid local data falls back to normal route entry. */
      }
    }
    return BookingWizardRouteArgs(
      serviceType: service,
      initialStep: BookingWizardSteps.route,
    );
  }
}

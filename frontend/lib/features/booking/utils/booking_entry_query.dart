import '../models/booking_wizard_route_args.dart';
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
    return BookingWizardRouteArgs(
      serviceType: service,
      initialStep: BookingWizardSteps.route,
    );
  }
}

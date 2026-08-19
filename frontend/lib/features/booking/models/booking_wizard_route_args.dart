import 'booking_wizard_steps.dart';
import 'location_option.dart';
import 'service_type_option.dart';

class BookingWizardRouteArgs {
  const BookingWizardRouteArgs({
    required this.serviceType,
    required this.origin,
    required this.destination,
    this.initialStep = BookingWizardSteps.schedule,
  });

  final BookingServiceType serviceType;
  final LocationOption origin;
  final LocationOption destination;
  final int initialStep;
}

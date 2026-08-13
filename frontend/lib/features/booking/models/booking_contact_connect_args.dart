import 'booking_complete_review.dart';
import 'booking_create_result.dart';
import 'location_option.dart';
import '../widgets/airport_meeting_guide_card.dart';

/// Navigation payload for [BookingContactConnectPage] after booking create.
class BookingContactConnectArgs {
  const BookingContactConnectArgs({
    required this.result,
    required this.serviceLabel,
    this.origin,
    this.destination,
    this.review,
    this.serviceTypeCode,
    this.originAirportCode,
    this.nameSignRequested = false,
    this.customerPhone,
    this.scheduledPickupAt,
    this.selectedVehicle,
    this.isUrgent = false,
    this.meetingVehicleInfo,
  });

  final BookingCreateResult result;
  final String serviceLabel;
  final LocationOption? origin;
  final LocationOption? destination;
  final BookingCompleteReview? review;
  final String? serviceTypeCode;
  final String? originAirportCode;
  final bool nameSignRequested;
  final String? customerPhone;
  final String? scheduledPickupAt;
  final String? selectedVehicle;
  final bool isUrgent;
  final AirportMeetingVehicleInfo? meetingVehicleInfo;
}

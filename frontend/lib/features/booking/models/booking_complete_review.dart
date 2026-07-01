import 'pricing_result.dart';
import 'service_type_option.dart';

/// Snapshot of wizard booking details for the complete-page review section.
/// Excludes fields already shown elsewhere on the complete page.
class BookingCompleteReview {
  final String? pickupDate;
  final String? pickupTime;
  final BookingServiceType? serviceType;
  final String flightNumber;
  final int adults;
  final int children;
  final int infants;
  final int luggage20;
  final int luggage24;
  final int golfBags;
  final int specialLuggageCount;
  final bool nameSign;
  final String? selectedVehicle;
  final PricingResult? pricing;
  final String customerName;
  final String customerEmail;
  final String customerPhone;
  final String customerCountryCode;
  final String messengerType;
  final String messengerId;
  final String additionalRequests;

  const BookingCompleteReview({
    this.pickupDate,
    this.pickupTime,
    this.serviceType,
    this.flightNumber = '',
    this.adults = 1,
    this.children = 0,
    this.infants = 0,
    this.luggage20 = 0,
    this.luggage24 = 0,
    this.golfBags = 0,
    this.specialLuggageCount = 0,
    this.nameSign = false,
    this.selectedVehicle,
    this.pricing,
    this.customerName = '',
    this.customerEmail = '',
    this.customerPhone = '',
    this.customerCountryCode = '',
    this.messengerType = '',
    this.messengerId = '',
    this.additionalRequests = '',
  });

  bool get showFlightNumber =>
      serviceType == BookingServiceType.airportPickup &&
      flightNumber.trim().isNotEmpty;

  bool get showCountryCode => customerCountryCode.trim().isNotEmpty;

  bool get showMessenger =>
      messengerType.trim().isNotEmpty || messengerId.trim().isNotEmpty;

  bool get showAdditionalRequests => additionalRequests.trim().isNotEmpty;

  bool get showPricingBreakdown =>
      pricing != null && pricing!.chargeItems.isNotEmpty;
}

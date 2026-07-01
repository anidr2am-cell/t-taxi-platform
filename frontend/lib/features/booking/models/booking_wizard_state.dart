import 'location_option.dart';
import 'pricing_result.dart';
import 'service_type_option.dart';
import 'vehicle_recommendation.dart';

class BookingWizardState {
  final int step;
  final BookingServiceType? serviceType;
  final LocationOption? origin;
  final LocationOption? destination;
  final String? pickupDate;
  final String? pickupTime;
  final int adults;
  final int children;
  final int infants;
  final int luggage20;
  final int luggage24;
  final int golfBags;
  final int specialLuggageCount;
  final bool nameSign;
  final VehicleRecommendation? recommendation;
  final String? selectedVehicle;
  final PricingResult? pricing;
  final String? errorMessage;
  final String customerName;
  final String customerEmail;
  final String customerPhone;
  final String customerCountryCode;
  final String messengerType;
  final String messengerId;
  final String additionalRequests;
  final String flightNumber;

  const BookingWizardState({
    this.step = 0,
    this.serviceType,
    this.origin,
    this.destination,
    this.pickupDate,
    this.pickupTime,
    this.adults = 1,
    this.children = 0,
    this.infants = 0,
    this.luggage20 = 0,
    this.luggage24 = 0,
    this.golfBags = 0,
    this.specialLuggageCount = 0,
    this.nameSign = false,
    this.recommendation,
    this.selectedVehicle,
    this.pricing,
    this.errorMessage,
    this.customerName = '',
    this.customerEmail = '',
    this.customerPhone = '',
    this.customerCountryCode = '',
    this.messengerType = '',
    this.messengerId = '',
    this.additionalRequests = '',
    this.flightNumber = '',
  });

  static const int stepCount = 7;

  BookingWizardState copyWith({
    int? step,
    BookingServiceType? serviceType,
    LocationOption? origin,
    LocationOption? destination,
    bool clearOrigin = false,
    bool clearDestination = false,
    String? pickupDate,
    String? pickupTime,
    bool clearPickupDateTime = false,
    int? adults,
    int? children,
    int? infants,
    int? luggage20,
    int? luggage24,
    int? golfBags,
    int? specialLuggageCount,
    bool? nameSign,
    VehicleRecommendation? recommendation,
    bool clearRecommendation = false,
    bool clearSelectedVehicle = false,
    String? selectedVehicle,
    PricingResult? pricing,
    bool clearPricing = false,
    String? errorMessage,
    bool clearError = false,
    String? customerName,
    String? customerEmail,
    String? customerPhone,
    String? customerCountryCode,
    String? messengerType,
    String? messengerId,
    String? additionalRequests,
    String? flightNumber,
  }) {
    return BookingWizardState(
      step: step ?? this.step,
      serviceType: serviceType ?? this.serviceType,
      origin: clearOrigin ? null : (origin ?? this.origin),
      destination: clearDestination ? null : (destination ?? this.destination),
      pickupDate: clearPickupDateTime ? null : (pickupDate ?? this.pickupDate),
      pickupTime: clearPickupDateTime ? null : (pickupTime ?? this.pickupTime),
      adults: adults ?? this.adults,
      children: children ?? this.children,
      infants: infants ?? this.infants,
      luggage20: luggage20 ?? this.luggage20,
      luggage24: luggage24 ?? this.luggage24,
      golfBags: golfBags ?? this.golfBags,
      specialLuggageCount: specialLuggageCount ?? this.specialLuggageCount,
      nameSign: nameSign ?? this.nameSign,
      recommendation: clearRecommendation
          ? null
          : (recommendation ?? this.recommendation),
      selectedVehicle: clearSelectedVehicle
          ? null
          : (selectedVehicle ?? this.selectedVehicle),
      pricing: clearPricing ? null : (pricing ?? this.pricing),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      customerName: customerName ?? this.customerName,
      customerEmail: customerEmail ?? this.customerEmail,
      customerPhone: customerPhone ?? this.customerPhone,
      customerCountryCode: customerCountryCode ?? this.customerCountryCode,
      messengerType: messengerType ?? this.messengerType,
      messengerId: messengerId ?? this.messengerId,
      additionalRequests: additionalRequests ?? this.additionalRequests,
      flightNumber: flightNumber ?? this.flightNumber,
    );
  }

  Map<String, dynamic> toJson() => {
    'step': step,
    'serviceType': serviceType?.apiCode,
    'origin': origin?.toJson(),
    'destination': destination?.toJson(),
    'pickupDate': pickupDate,
    'pickupTime': pickupTime,
    'adults': adults,
    'children': children,
    'infants': infants,
    'luggage20': luggage20,
    'luggage24': luggage24,
    'golfBags': golfBags,
    'specialLuggageCount': specialLuggageCount,
    'nameSign': nameSign,
    'selectedVehicle': selectedVehicle,
    'customerName': customerName,
    'customerEmail': customerEmail,
    'customerPhone': customerPhone,
    'customerCountryCode': customerCountryCode,
    'messengerType': messengerType,
    'messengerId': messengerId,
    'additionalRequests': additionalRequests,
    'flightNumber': flightNumber,
  };

  factory BookingWizardState.fromJson(Map<String, dynamic> json) {
    return BookingWizardState(
      step: json['step'] as int? ?? 0,
      serviceType: BookingServiceTypeX.fromApiCode(
        json['serviceType'] as String?,
      ),
      origin: json['origin'] != null
          ? LocationOption.fromJson(
              Map<String, dynamic>.from(json['origin'] as Map),
            )
          : null,
      destination: json['destination'] != null
          ? LocationOption.fromJson(
              Map<String, dynamic>.from(json['destination'] as Map),
            )
          : null,
      pickupDate: json['pickupDate'] as String?,
      pickupTime: json['pickupTime'] as String?,
      adults: json['adults'] as int? ?? 1,
      children: json['children'] as int? ?? 0,
      infants: json['infants'] as int? ?? 0,
      luggage20: json['luggage20'] as int? ?? 0,
      luggage24: json['luggage24'] as int? ?? 0,
      golfBags: json['golfBags'] as int? ?? 0,
      specialLuggageCount: json['specialLuggageCount'] as int? ?? 0,
      nameSign: json['nameSign'] as bool? ?? false,
      selectedVehicle: json['selectedVehicle'] as String?,
      customerName: json['customerName'] as String? ?? '',
      customerEmail: json['customerEmail'] as String? ?? '',
      customerPhone: json['customerPhone'] as String? ?? '',
      customerCountryCode: json['customerCountryCode'] as String? ?? '',
      messengerType: json['messengerType'] as String? ?? '',
      messengerId: json['messengerId'] as String? ?? '',
      additionalRequests: json['additionalRequests'] as String? ?? '',
      flightNumber: json['flightNumber'] as String? ?? '',
    );
  }
}

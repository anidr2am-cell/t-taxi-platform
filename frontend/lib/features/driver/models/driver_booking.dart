class DriverBooking {
  const DriverBooking({
    required this.bookingNumber,
    required this.status,
    this.assignmentStatus,
    this.acceptedAt,
    this.scheduledPickupAt,
    this.standbyReferenceTimeType,
    this.standbyReferenceTime,
    this.standbyAllowedAt,
    this.standbyConfirmed = false,
    this.standbyConfirmedAt,
    this.canConfirmStandby = false,
    required this.serviceTypeName,
    required this.pickupDate,
    required this.pickupTime,
    required this.origin,
    required this.destination,
    this.pickupLocation,
    this.destinationLocation,
    this.originLatitude,
    this.originLongitude,
    this.destinationLatitude,
    this.destinationLongitude,
    required this.passengerCount,
    required this.vehicleTypeName,
    this.customerDisplayName,
    this.flightNumber,
    this.flightStatus,
    this.latestEstimatedArrival,
    this.customerPhone,
    this.passengers,
    this.luggage,
    this.flight,
    this.specialInstructions,
    this.nameSignRequested = false,
    this.customerPaymentAmount,
    this.customerPaymentCurrency,
    this.customerPaymentMethod,
    this.companyCommissionAmount,
    this.companyCommissionCurrency,
    this.driverExpectedIncomeAmount,
    this.driverExpectedIncomeCurrency,
    this.currency,
    this.paymentMethodLabel,
    this.qr,
    this.allowedActions = const [],
    this.releaseAssignmentAvailable = false,
    this.releaseAssignmentEmergencyOnly = false,
    this.assignmentReleaseDeadline,
    this.assignmentReleaseBlockedReason,
  });

  final String bookingNumber;
  final String status;
  final String? assignmentStatus;
  final String? acceptedAt;
  final String? scheduledPickupAt;
  final String? standbyReferenceTimeType;
  final String? standbyReferenceTime;
  final String? standbyAllowedAt;
  final bool standbyConfirmed;
  final String? standbyConfirmedAt;
  final bool canConfirmStandby;
  final String serviceTypeName;
  final String pickupDate;
  final String pickupTime;
  final String origin;
  final String destination;
  final DriverBookingLocation? pickupLocation;
  final DriverBookingLocation? destinationLocation;
  final double? originLatitude;
  final double? originLongitude;
  final double? destinationLatitude;
  final double? destinationLongitude;
  final int passengerCount;
  final String vehicleTypeName;
  final String? customerDisplayName;
  final String? flightNumber;
  final String? flightStatus;
  final String? latestEstimatedArrival;
  final String? customerPhone;
  final Map<String, dynamic>? passengers;
  final Map<String, dynamic>? luggage;
  final Map<String, dynamic>? flight;
  final String? specialInstructions;
  final bool nameSignRequested;
  final double? customerPaymentAmount;
  final String? customerPaymentCurrency;
  final String? customerPaymentMethod;
  final double? companyCommissionAmount;
  final String? companyCommissionCurrency;
  final double? driverExpectedIncomeAmount;
  final String? driverExpectedIncomeCurrency;
  final String? currency;
  final String? paymentMethodLabel;
  final Map<String, dynamic>? qr;
  final List<String> allowedActions;
  final bool releaseAssignmentAvailable;
  final bool releaseAssignmentEmergencyOnly;
  final String? assignmentReleaseDeadline;
  final String? assignmentReleaseBlockedReason;

  bool get hasRouteCoordinates =>
      originLatitude != null &&
      originLongitude != null &&
      destinationLatitude != null &&
      destinationLongitude != null;

  bool get hasAnyRouteCoordinate =>
      (originLatitude != null && originLongitude != null) ||
      (destinationLatitude != null && destinationLongitude != null);

  factory DriverBooking.fromJson(Map<String, dynamic> json) {
    final serviceType = Map<String, dynamic>.from(
      json['serviceType'] as Map? ?? {},
    );
    final vehicleType = Map<String, dynamic>.from(
      json['vehicleType'] as Map? ?? {},
    );
    final capabilities = Map<String, dynamic>.from(
      json['capabilities'] as Map? ?? {},
    );
    return DriverBooking(
      bookingNumber: json['bookingNumber'] as String? ?? '',
      status: json['status'] as String? ?? '',
      assignmentStatus: json['assignmentStatus'] as String?,
      acceptedAt: json['acceptedAt'] as String?,
      scheduledPickupAt: json['scheduledPickupAt'] as String?,
      standbyReferenceTimeType: json['standbyReferenceTimeType'] as String?,
      standbyReferenceTime: json['standbyReferenceTime'] as String?,
      standbyAllowedAt: json['standbyAllowedAt'] as String?,
      standbyConfirmed: json['standbyConfirmed'] == true,
      standbyConfirmedAt: json['standbyConfirmedAt'] as String?,
      canConfirmStandby: json['canConfirmStandby'] == true,
      serviceTypeName:
          serviceType['name'] as String? ??
          serviceType['code'] as String? ??
          '',
      pickupDate: json['pickupDate'] as String? ?? '',
      pickupTime: json['pickupTime'] as String? ?? '',
      origin: json['origin'] as String? ?? '',
      destination: json['destination'] as String? ?? '',
      pickupLocation: DriverBookingLocation.fromJsonOrNull(
        json['pickupLocation'],
      ),
      destinationLocation: DriverBookingLocation.fromJsonOrNull(
        json['destinationLocation'],
      ),
      originLatitude: (json['originLatitude'] as num?)?.toDouble(),
      originLongitude: (json['originLongitude'] as num?)?.toDouble(),
      destinationLatitude: (json['destinationLatitude'] as num?)?.toDouble(),
      destinationLongitude: (json['destinationLongitude'] as num?)?.toDouble(),
      passengerCount: (json['passengerCount'] as num?)?.toInt() ?? 0,
      vehicleTypeName:
          vehicleType['name'] as String? ??
          vehicleType['code'] as String? ??
          '',
      customerDisplayName: json['customerDisplayName'] as String?,
      flightNumber: json['flightNumber'] as String?,
      flightStatus: json['flightStatus'] as String?,
      latestEstimatedArrival: json['latestEstimatedArrival'] as String?,
      customerPhone: json['customerPhone'] as String?,
      passengers: json['passengers'] == null
          ? null
          : Map<String, dynamic>.from(json['passengers'] as Map),
      luggage: json['luggage'] == null
          ? null
          : Map<String, dynamic>.from(json['luggage'] as Map),
      flight: json['flight'] == null
          ? null
          : Map<String, dynamic>.from(json['flight'] as Map),
      specialInstructions: json['specialInstructions'] as String?,
      nameSignRequested: json['nameSignRequested'] == true,
      customerPaymentAmount: (json['customerPaymentAmount'] as num?)
          ?.toDouble(),
      customerPaymentCurrency: json['customerPaymentCurrency'] as String?,
      customerPaymentMethod: json['customerPaymentMethod'] as String?,
      companyCommissionAmount: (json['companyCommissionAmount'] as num?)
          ?.toDouble(),
      companyCommissionCurrency: json['companyCommissionCurrency'] as String?,
      driverExpectedIncomeAmount: (json['driverExpectedIncomeAmount'] as num?)
          ?.toDouble(),
      driverExpectedIncomeCurrency:
          json['driverExpectedIncomeCurrency'] as String?,
      currency: json['currency'] as String?,
      paymentMethodLabel: json['paymentMethodLabel'] as String?,
      qr: json['qr'] == null
          ? null
          : Map<String, dynamic>.from(json['qr'] as Map),
      allowedActions: (json['allowedActions'] as List? ?? [])
          .map((item) => item.toString())
          .toList(),
      releaseAssignmentAvailable:
          capabilities['releaseAssignmentAvailable'] == true ||
          (json['allowedActions'] as List? ?? []).contains('RELEASE_ASSIGNMENT'),
      releaseAssignmentEmergencyOnly:
          capabilities['releaseAssignmentEmergencyOnly'] == true,
      assignmentReleaseDeadline:
          capabilities['assignmentReleaseDeadline'] as String?,
      assignmentReleaseBlockedReason:
          capabilities['assignmentReleaseBlockedReason'] as String?,
    );
  }
}

class DriverBookingLocation {
  const DriverBookingLocation({
    this.name,
    this.address,
    this.latitude,
    this.longitude,
    this.placeId,
  });

  final String? name;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String? placeId;

  bool get hasCoordinates => latitude != null && longitude != null;

  String get displayName {
    final trimmedName = name?.trim();
    if (trimmedName != null && trimmedName.isNotEmpty) return trimmedName;
    final trimmedAddress = address?.trim();
    if (trimmedAddress != null && trimmedAddress.isNotEmpty) {
      return trimmedAddress;
    }
    return '';
  }

  String? get secondaryAddress {
    final trimmedName = name?.trim();
    final trimmedAddress = address?.trim();
    if (trimmedAddress == null || trimmedAddress.isEmpty) return null;
    if (trimmedName != null && trimmedName.isNotEmpty) {
      if (trimmedName == trimmedAddress) return null;
      return trimmedAddress;
    }
    return null;
  }

  static DriverBookingLocation? fromJsonOrNull(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    return DriverBookingLocation(
      name: json['name'] as String?,
      address: json['address'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      placeId: json['placeId'] as String?,
    );
  }
}

class DriverJobsToday {
  const DriverJobsToday({required this.date, required this.items});

  final String date;
  final List<DriverBooking> items;

  factory DriverJobsToday.fromJson(Map<String, dynamic> json) {
    return DriverJobsToday(
      date: json['date'] as String? ?? '',
      items: (json['items'] as List? ?? [])
          .map(
            (item) =>
                DriverBooking.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
    );
  }
}

class DriverOpenCall {
  const DriverOpenCall({
    required this.bookingNumber,
    required this.status,
    required this.pickupDate,
    required this.pickupTime,
    required this.origin,
    required this.destination,
    required this.serviceTypeName,
    required this.vehicleTypeName,
    required this.amount,
    required this.currency,
    required this.passengerCount,
    this.customerPaymentAmount,
    this.customerPaymentCurrency,
    this.customerPaymentMethod,
    this.companyCommissionAmount,
    this.companyCommissionCurrency,
    this.driverExpectedIncomeAmount,
    this.driverExpectedIncomeCurrency,
    this.luggage,
    this.isUrgentRequest = false,
    this.negotiationId,
    this.minRequiredEtaMinutes,
  });

  final String bookingNumber;
  final String status;
  final String pickupDate;
  final String pickupTime;
  final String origin;
  final String destination;
  final String serviceTypeName;
  final String vehicleTypeName;
  final double amount;
  final String currency;
  final int passengerCount;
  final double? customerPaymentAmount;
  final String? customerPaymentCurrency;
  final String? customerPaymentMethod;
  final double? companyCommissionAmount;
  final String? companyCommissionCurrency;
  final double? driverExpectedIncomeAmount;
  final String? driverExpectedIncomeCurrency;
  final Map<String, dynamic>? luggage;
  final bool isUrgentRequest;
  final int? negotiationId;
  final int? minRequiredEtaMinutes;

  DriverOpenCall copyWith({
    bool? isUrgentRequest,
    int? negotiationId,
    int? minRequiredEtaMinutes,
  }) {
    return DriverOpenCall(
      bookingNumber: bookingNumber,
      status: status,
      pickupDate: pickupDate,
      pickupTime: pickupTime,
      origin: origin,
      destination: destination,
      serviceTypeName: serviceTypeName,
      vehicleTypeName: vehicleTypeName,
      amount: amount,
      currency: currency,
      passengerCount: passengerCount,
      customerPaymentAmount: customerPaymentAmount,
      customerPaymentCurrency: customerPaymentCurrency,
      customerPaymentMethod: customerPaymentMethod,
      companyCommissionAmount: companyCommissionAmount,
      companyCommissionCurrency: companyCommissionCurrency,
      driverExpectedIncomeAmount: driverExpectedIncomeAmount,
      driverExpectedIncomeCurrency: driverExpectedIncomeCurrency,
      luggage: luggage,
      isUrgentRequest: isUrgentRequest ?? this.isUrgentRequest,
      negotiationId: negotiationId ?? this.negotiationId,
      minRequiredEtaMinutes:
          minRequiredEtaMinutes ?? this.minRequiredEtaMinutes,
    );
  }

  factory DriverOpenCall.fromJson(Map<String, dynamic> json) {
    final serviceType = Map<String, dynamic>.from(
      json['serviceType'] as Map? ?? {},
    );
    final vehicleType = Map<String, dynamic>.from(
      json['vehicleType'] as Map? ?? {},
    );
    return DriverOpenCall(
      bookingNumber: json['bookingNumber'] as String? ?? '',
      status: json['status'] as String? ?? '',
      pickupDate: json['pickupDate'] as String? ?? '',
      pickupTime: json['pickupTime'] as String? ?? '',
      origin: json['origin'] as String? ?? '',
      destination: json['destination'] as String? ?? '',
      serviceTypeName:
          serviceType['name'] as String? ??
          serviceType['code'] as String? ??
          '',
      vehicleTypeName:
          vehicleType['name'] as String? ??
          vehicleType['code'] as String? ??
          '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      currency: json['currency'] as String? ?? '',
      passengerCount: (json['passengerCount'] as num?)?.toInt() ?? 0,
      customerPaymentAmount: (json['customerPaymentAmount'] as num?)
          ?.toDouble(),
      customerPaymentCurrency: json['customerPaymentCurrency'] as String?,
      customerPaymentMethod: json['customerPaymentMethod'] as String?,
      companyCommissionAmount: (json['companyCommissionAmount'] as num?)
          ?.toDouble(),
      companyCommissionCurrency: json['companyCommissionCurrency'] as String?,
      driverExpectedIncomeAmount: (json['driverExpectedIncomeAmount'] as num?)
          ?.toDouble(),
      driverExpectedIncomeCurrency:
          json['driverExpectedIncomeCurrency'] as String?,
      luggage: json['luggage'] == null
          ? null
          : Map<String, dynamic>.from(json['luggage'] as Map),
      isUrgentRequest: json['isUrgentRequest'] == true,
      negotiationId: (json['negotiationId'] as num?)?.toInt(),
      minRequiredEtaMinutes: (json['minRequiredEtaMinutes'] as num?)?.toInt(),
    );
  }
}

class DriverOpenCalls {
  const DriverOpenCalls({
    required this.items,
    this.blockedReason,
    this.message,
  });

  final List<DriverOpenCall> items;
  final String? blockedReason;
  final String? message;

  factory DriverOpenCalls.fromJson(Map<String, dynamic> json) {
    return DriverOpenCalls(
      items: (json['items'] as List? ?? [])
          .map(
            (item) =>
                DriverOpenCall.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
      blockedReason: json['blockedReason'] as String?,
      message: json['message'] as String?,
    );
  }
}

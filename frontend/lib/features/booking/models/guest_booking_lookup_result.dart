class GuestBookingLookupResult {
  const GuestBookingLookupResult({
    this.bookingId,
    required this.bookingNumber,
    required this.status,
    required this.scheduledPickupAt,
    required this.serviceTypeName,
    required this.originAddress,
    required this.destinationAddress,
    required this.totalAmount,
    required this.currency,
    required this.paymentMethod,
    required this.guestAccessToken,
    required this.guestAccessExpiresAt,
    required this.capabilities,
    this.serviceTypeCode,
    this.originAirportCode,
    this.nameSignRequested = false,
    this.vehicleType,
    this.vehicleColor,
    this.vehiclePlateNumber,
    this.driverName,
    this.driverPhone,
  });

  final int? bookingId;
  final String bookingNumber;
  final String status;
  final String? scheduledPickupAt;
  final String serviceTypeName;
  final String originAddress;
  final String destinationAddress;
  final num totalAmount;
  final String currency;
  final String paymentMethod;
  final String guestAccessToken;
  final String? guestAccessExpiresAt;
  final GuestBookingCapabilities capabilities;
  final String? serviceTypeCode;
  final String? originAirportCode;
  final bool nameSignRequested;
  final String? vehicleType;
  final String? vehicleColor;
  final String? vehiclePlateNumber;
  final String? driverName;
  final String? driverPhone;

  factory GuestBookingLookupResult.fromJson(Map<String, dynamic> json) {
    final route = Map<String, dynamic>.from(json['route'] as Map? ?? {});
    final origin = Map<String, dynamic>.from(route['origin'] as Map? ?? {});
    final destination = Map<String, dynamic>.from(
      route['destination'] as Map? ?? {},
    );
    final serviceType = Map<String, dynamic>.from(
      json['serviceType'] as Map? ?? {},
    );
    final options = Map<String, dynamic>.from(json['options'] as Map? ?? {});
    final pricing = Map<String, dynamic>.from(json['pricing'] as Map? ?? {});
    final vehicle = Map<String, dynamic>.from(json['vehicle'] as Map? ?? {});
    final guestAccess = Map<String, dynamic>.from(
      json['guestAccess'] as Map? ?? {},
    );
    final driver = json['assignedDriver'] is Map
        ? Map<String, dynamic>.from(json['assignedDriver'] as Map)
        : null;
    final driverVehicle = driver?['vehicle'] is Map
        ? Map<String, dynamic>.from(driver!['vehicle'] as Map)
        : <String, dynamic>{};

    final bookingNumber = json['bookingNumber'] as String? ?? '';
    final token = guestAccess['token'] as String? ?? '';
    if (bookingNumber.isEmpty || token.isEmpty) {
      throw const FormatException('Invalid booking lookup response');
    }

    return GuestBookingLookupResult(
      bookingId: json['bookingId'] as int?,
      bookingNumber: bookingNumber,
      status: json['status'] as String? ?? '',
      scheduledPickupAt: json['scheduledPickupAt'] as String?,
      serviceTypeName: serviceType['name'] as String? ?? '',
      originAddress: origin['address'] as String? ?? '',
      destinationAddress: destination['address'] as String? ?? '',
      totalAmount: pricing['totalAmount'] as num? ?? 0,
      currency: pricing['currency'] as String? ?? 'THB',
      paymentMethod: pricing['paymentMethod'] as String? ?? 'PAY_DRIVER',
      guestAccessToken: token,
      guestAccessExpiresAt: guestAccess['expiresAt'] as String?,
      capabilities: GuestBookingCapabilities.fromJson(
        Map<String, dynamic>.from(json['capabilities'] as Map? ?? {}),
      ),
      serviceTypeCode: _firstString([
        serviceType['code'],
        serviceType['serviceTypeCode'],
        json['serviceTypeCode'],
      ]),
      originAirportCode: _firstString([
        origin['airportIata'],
        origin['iata'],
        origin['code'],
        origin['locationCode'],
        json['originAirportIata'],
      ]),
      nameSignRequested:
          options['nameSign'] == true ||
          options['nameSignRequested'] == true ||
          json['nameSignRequested'] == true,
      vehicleType: _firstString([
        driverVehicle['typeName'],
        driverVehicle['typeCode'],
        vehicle['typeName'],
        vehicle['typeCode'],
      ]),
      vehicleColor: _firstString([driverVehicle['color'], vehicle['color']]),
      vehiclePlateNumber: _firstString([
        driverVehicle['plateNumber'],
        driverVehicle['vehiclePlateNumber'],
        driverVehicle['licensePlate'],
        vehicle['plateNumber'],
        vehicle['vehiclePlateNumber'],
        vehicle['licensePlate'],
      ]),
      driverName: driver?['name'] as String?,
      driverPhone: driver?['phone'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'bookingId': bookingId,
    'bookingNumber': bookingNumber,
    'status': status,
    'scheduledPickupAt': scheduledPickupAt,
    'serviceType': {'code': serviceTypeCode, 'name': serviceTypeName},
    'route': {
      'origin': {'address': originAddress, 'code': originAirportCode},
      'destination': {'address': destinationAddress},
    },
    'options': {'nameSignRequested': nameSignRequested},
    'vehicle': {
      'typeName': vehicleType,
      'color': vehicleColor,
      'plateNumber': vehiclePlateNumber,
    },
    'pricing': {
      'totalAmount': totalAmount,
      'currency': currency,
      'paymentMethod': paymentMethod,
    },
    'guestAccess': {
      'token': guestAccessToken,
      'expiresAt': guestAccessExpiresAt,
    },
    'capabilities': capabilities.toJson(),
    'assignedDriver': driverName == null
        ? null
        : {
            'name': driverName,
            'phone': driverPhone,
            'vehicle': {
              'typeName': vehicleType,
              'color': vehicleColor,
              'plateNumber': vehiclePlateNumber,
            },
          },
  };

  bool get hasValidGuestAccess {
    final value = guestAccessExpiresAt;
    if (value == null || value.isEmpty) return true;
    final expiresAt = DateTime.tryParse(value);
    if (expiresAt == null) return false;
    return expiresAt.isAfter(DateTime.now());
  }

  static String? _firstString(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }
}

class GuestBookingCapabilities {
  const GuestBookingCapabilities({
    required this.chatAvailable,
    required this.notificationsAvailable,
    required this.dropoffQrIssueAvailable,
    required this.reviewAvailable,
    required this.boardingQrRecoverable,
    required this.boardingQrPreviouslyIssued,
  });

  final bool chatAvailable;
  final bool notificationsAvailable;
  final bool dropoffQrIssueAvailable;
  final bool reviewAvailable;
  final bool boardingQrRecoverable;
  final bool boardingQrPreviouslyIssued;

  factory GuestBookingCapabilities.fromJson(Map<String, dynamic> json) {
    return GuestBookingCapabilities(
      chatAvailable: json['chatAvailable'] == true,
      notificationsAvailable: json['notificationsAvailable'] != false,
      dropoffQrIssueAvailable: json['dropoffQrIssueAvailable'] == true,
      reviewAvailable: json['reviewAvailable'] == true,
      boardingQrRecoverable: json['boardingQrRecoverable'] == true,
      boardingQrPreviouslyIssued: json['boardingQrPreviouslyIssued'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'chatAvailable': chatAvailable,
    'notificationsAvailable': notificationsAvailable,
    'dropoffQrIssueAvailable': dropoffQrIssueAvailable,
    'reviewAvailable': reviewAvailable,
    'boardingQrRecoverable': boardingQrRecoverable,
    'boardingQrPreviouslyIssued': boardingQrPreviouslyIssued,
  };
}

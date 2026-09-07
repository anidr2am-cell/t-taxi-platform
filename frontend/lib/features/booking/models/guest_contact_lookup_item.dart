class GuestContactLookupItem {
  const GuestContactLookupItem({
    required this.bookingNumber,
    required this.status,
    this.scheduledPickupDate,
    this.pickupTimePeriod,
    required this.serviceTypeName,
    this.serviceTypeCode,
    this.originName,
    this.destinationName,
    this.originCode,
    this.destinationCode,
    this.passengerTotal,
    this.luggageTotalPieces,
    this.reassignmentInProgress = false,
  });

  final String bookingNumber;
  final String status;
  final String? scheduledPickupDate;
  final String? pickupTimePeriod;
  final String serviceTypeName;
  final String? serviceTypeCode;
  final String? originName;
  final String? destinationName;
  final String? originCode;
  final String? destinationCode;
  final int? passengerTotal;
  final int? luggageTotalPieces;
  final bool reassignmentInProgress;

  factory GuestContactLookupItem.fromJson(Map<String, dynamic> json) {
    final route = Map<String, dynamic>.from(json['route'] as Map? ?? {});
    final origin = Map<String, dynamic>.from(route['origin'] as Map? ?? {});
    final destination = Map<String, dynamic>.from(
      route['destination'] as Map? ?? {},
    );
    final serviceType = Map<String, dynamic>.from(
      json['serviceType'] as Map? ?? {},
    );
    final passengers = Map<String, dynamic>.from(
      json['passengers'] as Map? ?? {},
    );
    final luggage = Map<String, dynamic>.from(json['luggage'] as Map? ?? {});

    return GuestContactLookupItem(
      bookingNumber: json['bookingNumber'] as String? ?? '',
      status: json['status'] as String? ?? '',
      scheduledPickupDate: json['scheduledPickupAt'] as String?,
      pickupTimePeriod: json['pickupTimePeriod'] as String?,
      serviceTypeName: serviceType['name'] as String? ?? '',
      serviceTypeCode: serviceType['code'] as String?,
      originName: origin['name'] as String?,
      destinationName: destination['name'] as String?,
      originCode: origin['code'] as String?,
      destinationCode: destination['code'] as String?,
      passengerTotal: passengers['total'] as int?,
      luggageTotalPieces: luggage['totalPieces'] as int?,
      reassignmentInProgress: json['reassignmentInProgress'] == true,
    );
  }
}

class GuestContactLookupResponse {
  const GuestContactLookupResponse({
    required this.bookings,
  });

  final List<GuestContactLookupItem> bookings;

  factory GuestContactLookupResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['bookings'];
    final bookings = raw is List
        ? raw
            .whereType<Map>()
            .map((item) => GuestContactLookupItem.fromJson(
                  Map<String, dynamic>.from(item),
                ))
            .toList(growable: false)
        : const <GuestContactLookupItem>[];
    return GuestContactLookupResponse(bookings: bookings);
  }
}

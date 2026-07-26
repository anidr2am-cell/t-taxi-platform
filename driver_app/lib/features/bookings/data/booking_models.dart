import '../../../core/network/api_exception.dart';

enum BookingStatusCode {
  pending,
  open,
  confirmed,
  driverAssigned,
  onRoute,
  driverArrived,
  pickedUp,
  settlementPending,
  completed,
  cancelled,
  noShow,
  unknown,
}

class BookingStatus {
  const BookingStatus(this.raw, this.code);

  factory BookingStatus.parse(String raw) {
    final code = switch (raw) {
      'PENDING' => BookingStatusCode.pending,
      'OPEN' => BookingStatusCode.open,
      'CONFIRMED' => BookingStatusCode.confirmed,
      'DRIVER_ASSIGNED' => BookingStatusCode.driverAssigned,
      'ON_ROUTE' => BookingStatusCode.onRoute,
      'DRIVER_ARRIVED' => BookingStatusCode.driverArrived,
      'PICKED_UP' => BookingStatusCode.pickedUp,
      'SETTLEMENT_PENDING' => BookingStatusCode.settlementPending,
      'COMPLETED' => BookingStatusCode.completed,
      'CANCELLED' => BookingStatusCode.cancelled,
      'NO_SHOW' => BookingStatusCode.noShow,
      _ => BookingStatusCode.unknown,
    };
    return BookingStatus(raw, code);
  }

  final String raw;
  final BookingStatusCode code;

  String get label => switch (code) {
    BookingStatusCode.pending => '접수 대기',
    BookingStatusCode.open => '배차 대기',
    BookingStatusCode.confirmed => '예약 확정',
    BookingStatusCode.driverAssigned => '기사 배정',
    BookingStatusCode.onRoute => '이동 중',
    BookingStatusCode.driverArrived => '기사 도착',
    BookingStatusCode.pickedUp => '고객 탑승',
    BookingStatusCode.settlementPending => '정산 대기',
    BookingStatusCode.completed => '운행 완료',
    BookingStatusCode.cancelled => '예약 취소',
    BookingStatusCode.noShow => '노쇼',
    BookingStatusCode.unknown => '알 수 없는 상태',
  };
}

enum AssignmentStatusCode {
  assigned,
  accepted,
  rejected,
  completed,
  cancelled,
  unknown,
}

class AssignmentStatus {
  const AssignmentStatus(this.raw, this.code);

  factory AssignmentStatus.parse(Object? value) {
    if (value == null) {
      return const AssignmentStatus(null, AssignmentStatusCode.unknown);
    }
    if (value is! String) {
      return const AssignmentStatus(null, AssignmentStatusCode.unknown);
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return const AssignmentStatus(null, AssignmentStatusCode.unknown);
    }
    final code = switch (trimmed) {
      'ASSIGNED' => AssignmentStatusCode.assigned,
      'ACCEPTED' => AssignmentStatusCode.accepted,
      'REJECTED' => AssignmentStatusCode.rejected,
      'COMPLETED' => AssignmentStatusCode.completed,
      'CANCELLED' => AssignmentStatusCode.cancelled,
      _ => AssignmentStatusCode.unknown,
    };
    return AssignmentStatus(trimmed, code);
  }

  final String? raw;
  final AssignmentStatusCode code;

  bool get isAssigned => code == AssignmentStatusCode.assigned;
  bool get isAccepted => code == AssignmentStatusCode.accepted;
}

class BookingType {
  const BookingType({required this.code, required this.name});

  factory BookingType.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      return const BookingType(code: '', name: '');
    }
    return BookingType(
      code: _optionalString(value['code']) ?? '',
      name: _optionalString(value['name']) ?? '',
    );
  }

  final String code;
  final String name;
}

class BookingMoney {
  const BookingMoney(this.amount, this.currency);

  factory BookingMoney.fromFields(Object? amount, Object? currency) {
    final parsedAmount = switch (amount) {
      num value => value,
      String value => num.tryParse(value),
      _ => null,
    };
    return BookingMoney(parsedAmount, _optionalString(currency));
  }

  final num? amount;
  final String? currency;

  bool get isAvailable => amount != null && currency != null;
}

class BookingLocation {
  const BookingLocation({
    this.name,
    this.address,
    this.latitude,
    this.longitude,
    this.placeId,
  });

  factory BookingLocation.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return const BookingLocation();
    return BookingLocation(
      name: _optionalString(value['name']),
      address: _optionalString(value['address']),
      latitude: _optionalDouble(value['latitude']),
      longitude: _optionalDouble(value['longitude']),
      placeId: _optionalString(value['placeId']),
    );
  }

  final String? name;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String? placeId;
}

class BookingCapabilities {
  const BookingCapabilities({
    required this.releaseAssignmentAvailable,
    required this.releaseAssignmentEmergencyOnly,
    required this.assignmentReleaseDeadline,
    required this.assignmentReleaseBlockedReason,
    required this.reassignmentPriority,
  });

  const BookingCapabilities.empty()
    : releaseAssignmentAvailable = false,
      releaseAssignmentEmergencyOnly = false,
      assignmentReleaseDeadline = null,
      assignmentReleaseBlockedReason = null,
      reassignmentPriority = null;

  factory BookingCapabilities.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      return const BookingCapabilities.empty();
    }
    return BookingCapabilities(
      releaseAssignmentAvailable: value['releaseAssignmentAvailable'] == true,
      releaseAssignmentEmergencyOnly:
          value['releaseAssignmentEmergencyOnly'] == true,
      assignmentReleaseDeadline: _optionalString(
        value['assignmentReleaseDeadline'],
      ),
      assignmentReleaseBlockedReason: _optionalString(
        value['assignmentReleaseBlockedReason'],
      ),
      reassignmentPriority: _optionalString(value['reassignmentPriority']),
    );
  }

  final bool releaseAssignmentAvailable;
  final bool releaseAssignmentEmergencyOnly;
  final String? assignmentReleaseDeadline;
  final String? assignmentReleaseBlockedReason;
  final String? reassignmentPriority;
}

class BookingSummary {
  const BookingSummary({
    required this.bookingNumber,
    required this.status,
    required this.assignmentStatus,
    required this.acceptedAt,
    required this.scheduledPickupAt,
    required this.standbyReferenceTimeType,
    required this.standbyReferenceTime,
    required this.standbyAllowedAt,
    required this.standbyConfirmed,
    required this.standbyConfirmedAt,
    required this.canConfirmStandby,
    required this.allowedActions,
    required this.pickupDate,
    required this.pickupTime,
    required this.origin,
    required this.destination,
    required this.pickupLocation,
    required this.destinationLocation,
    required this.originLatitude,
    required this.originLongitude,
    required this.destinationLatitude,
    required this.destinationLongitude,
    required this.passengerCount,
    required this.vehicleType,
    required this.customerDisplayName,
    required this.flightNumber,
    required this.driverExpectedIncome,
  });

  factory BookingSummary.fromJson(Map<String, dynamic> json) {
    final bookingNumber = json['bookingNumber'];
    final rawStatus = json['status'];
    final pickupDate = json['pickupDate'];
    final pickupTime = json['pickupTime'];
    final origin = json['origin'];
    final destination = json['destination'];
    if (bookingNumber is! String ||
        !RegExp(r'^TX\d{12}$').hasMatch(bookingNumber) ||
        rawStatus is! String ||
        pickupDate is! String ||
        !_isServiceDate(pickupDate) ||
        pickupTime is! String ||
        !RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(pickupTime) ||
        origin is! String ||
        destination is! String) {
      throw const ApiException(ApiFailureKind.invalidResponse);
    }
    final passengerCount = json['passengerCount'];
    if (passengerCount != null && passengerCount is! num) {
      throw const ApiException(ApiFailureKind.invalidResponse);
    }
    return BookingSummary(
      bookingNumber: bookingNumber,
      status: BookingStatus.parse(rawStatus),
      assignmentStatus: AssignmentStatus.parse(json['assignmentStatus']),
      acceptedAt: _optionalString(json['acceptedAt']),
      scheduledPickupAt: _optionalString(json['scheduledPickupAt']),
      standbyReferenceTimeType: _optionalString(
        json['standbyReferenceTimeType'],
      ),
      standbyReferenceTime: _optionalString(json['standbyReferenceTime']),
      standbyAllowedAt: _optionalString(json['standbyAllowedAt']),
      standbyConfirmed: json['standbyConfirmed'] == true,
      standbyConfirmedAt: _optionalString(json['standbyConfirmedAt']),
      canConfirmStandby: json['canConfirmStandby'] == true,
      allowedActions: _stringList(json['allowedActions']),
      pickupDate: pickupDate,
      pickupTime: pickupTime,
      origin: origin,
      destination: destination,
      pickupLocation: BookingLocation.fromJson(json['pickupLocation']),
      destinationLocation: BookingLocation.fromJson(
        json['destinationLocation'],
      ),
      originLatitude: _optionalDouble(json['originLatitude']),
      originLongitude: _optionalDouble(json['originLongitude']),
      destinationLatitude: _optionalDouble(json['destinationLatitude']),
      destinationLongitude: _optionalDouble(json['destinationLongitude']),
      passengerCount: passengerCount?.toInt(),
      vehicleType: BookingType.fromJson(json['vehicleType']),
      customerDisplayName: _optionalString(json['customerDisplayName']),
      flightNumber: _optionalString(json['flightNumber']),
      driverExpectedIncome: BookingMoney.fromFields(
        json['driverExpectedIncomeAmount'],
        json['driverExpectedIncomeCurrency'],
      ),
    );
  }

  final String bookingNumber;
  final BookingStatus status;
  final AssignmentStatus assignmentStatus;
  final String? acceptedAt;
  final String? scheduledPickupAt;
  final String? standbyReferenceTimeType;
  final String? standbyReferenceTime;
  final String? standbyAllowedAt;
  final bool standbyConfirmed;
  final String? standbyConfirmedAt;
  final bool canConfirmStandby;
  final List<String> allowedActions;
  final String pickupDate;
  final String pickupTime;
  final String origin;
  final String destination;
  final BookingLocation pickupLocation;
  final BookingLocation destinationLocation;
  final double? originLatitude;
  final double? originLongitude;
  final double? destinationLatitude;
  final double? destinationLongitude;
  final int? passengerCount;
  final BookingType vehicleType;
  final String? customerDisplayName;
  final String? flightNumber;
  final BookingMoney driverExpectedIncome;

  bool get canAccept =>
      canConfirmStandby &&
      standbyAllowedAt != null &&
      allowsAction('ACCEPT_BOOKING');

  bool allowsAction(String action) => allowedActions.contains(action);

  BookingSummary copyWith({
    BookingStatus? status,
    AssignmentStatus? assignmentStatus,
  }) => BookingSummary(
    bookingNumber: bookingNumber,
    status: status ?? this.status,
    assignmentStatus: assignmentStatus ?? this.assignmentStatus,
    acceptedAt: acceptedAt,
    scheduledPickupAt: scheduledPickupAt,
    standbyReferenceTimeType: standbyReferenceTimeType,
    standbyReferenceTime: standbyReferenceTime,
    standbyAllowedAt: standbyAllowedAt,
    standbyConfirmed: standbyConfirmed,
    standbyConfirmedAt: standbyConfirmedAt,
    canConfirmStandby: canConfirmStandby,
    allowedActions: allowedActions,
    pickupDate: pickupDate,
    pickupTime: pickupTime,
    origin: origin,
    destination: destination,
    pickupLocation: pickupLocation,
    destinationLocation: destinationLocation,
    originLatitude: originLatitude,
    originLongitude: originLongitude,
    destinationLatitude: destinationLatitude,
    destinationLongitude: destinationLongitude,
    passengerCount: passengerCount,
    vehicleType: vehicleType,
    customerDisplayName: customerDisplayName,
    flightNumber: flightNumber,
    driverExpectedIncome: driverExpectedIncome,
  );
}

class BookingList {
  const BookingList({required this.serviceDate, required this.items});

  factory BookingList.fromEnvelope(Map<String, dynamic> envelope) {
    final data = envelope['data'];
    if (envelope['success'] != true || data is! Map<String, dynamic>) {
      throw const ApiException(ApiFailureKind.invalidResponse);
    }
    final date = data['date'];
    final items = data['items'];
    if (date is! String || !_isServiceDate(date) || items is! List) {
      throw const ApiException(ApiFailureKind.invalidResponse);
    }
    return BookingList(
      serviceDate: date,
      items: List.unmodifiable(
        items.map((item) {
          if (item is! Map<String, dynamic>) {
            throw const ApiException(ApiFailureKind.invalidResponse);
          }
          return BookingSummary.fromJson(item);
        }),
      ),
    );
  }

  final String serviceDate;
  final List<BookingSummary> items;
}

class PassengerBreakdown {
  const PassengerBreakdown({this.adults, this.children, this.infants});

  factory PassengerBreakdown.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return const PassengerBreakdown();
    return PassengerBreakdown(
      adults: _optionalInt(value['adults']),
      children: _optionalInt(value['children']),
      infants: _optionalInt(value['infants']),
    );
  }

  final int? adults;
  final int? children;
  final int? infants;

  String? get display {
    final values = <String>[
      if (adults != null) '성인 $adults명',
      if (children != null) '아동 $children명',
      if (infants != null) '유아 $infants명',
    ];
    return values.isEmpty ? null : values.join(' · ');
  }
}

class LuggageBreakdown {
  const LuggageBreakdown({
    this.carriers20Inch,
    this.carriers24InchPlus,
    this.golfBags,
    this.specialItems,
  });

  factory LuggageBreakdown.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return const LuggageBreakdown();
    return LuggageBreakdown(
      carriers20Inch: _optionalInt(value['carriers20Inch']),
      carriers24InchPlus: _optionalInt(value['carriers24InchPlus']),
      golfBags: _optionalInt(value['golfBags']),
      specialItems: _optionalString(value['specialItems']),
    );
  }

  final int? carriers20Inch;
  final int? carriers24InchPlus;
  final int? golfBags;
  final String? specialItems;

  String? get display {
    final values = <String>[
      if (carriers20Inch != null) '20인치 $carriers20Inch개',
      if (carriers24InchPlus != null) '24인치 이상 $carriers24InchPlus개',
      if (golfBags != null) '골프백 $golfBags개',
      ?specialItems,
    ];
    return values.isEmpty ? null : values.join(' · ');
  }
}

class FlightInfo {
  const FlightInfo({
    this.flightNumber,
    this.flightStatus,
    this.latestEstimatedArrival,
    this.delayMinutes,
  });

  factory FlightInfo.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return const FlightInfo();
    return FlightInfo(
      flightNumber: _optionalString(value['flightNumber']),
      flightStatus: _optionalString(value['flightStatus']),
      latestEstimatedArrival: _optionalString(value['latestEstimatedArrival']),
      delayMinutes: _optionalInt(value['delayMinutes']),
    );
  }

  final String? flightNumber;
  final String? flightStatus;
  final String? latestEstimatedArrival;
  final int? delayMinutes;
}

class BookingDetail {
  const BookingDetail({
    required this.summary,
    required this.passengers,
    required this.luggage,
    required this.flight,
    required this.specialInstructions,
    required this.customerPayment,
    required this.companyCommission,
    required this.capabilities,
    required this.nameSignRequested,
  });

  factory BookingDetail.fromEnvelope(Map<String, dynamic> envelope) {
    final data = envelope['data'];
    if (envelope['success'] != true || data is! Map<String, dynamic>) {
      throw const ApiException(ApiFailureKind.invalidResponse);
    }
    return BookingDetail(
      summary: BookingSummary.fromJson(data),
      passengers: PassengerBreakdown.fromJson(data['passengers']),
      luggage: LuggageBreakdown.fromJson(data['luggage']),
      flight: FlightInfo.fromJson(data['flight']),
      specialInstructions: _optionalString(data['specialInstructions']),
      customerPayment: BookingMoney.fromFields(
        data['customerPaymentAmount'],
        data['customerPaymentCurrency'],
      ),
      companyCommission: BookingMoney.fromFields(
        data['companyCommissionAmount'],
        data['companyCommissionCurrency'],
      ),
      capabilities: BookingCapabilities.fromJson(data['capabilities']),
      nameSignRequested: data['nameSignRequested'] == true,
    );
  }

  final BookingSummary summary;
  final PassengerBreakdown passengers;
  final LuggageBreakdown luggage;
  final FlightInfo flight;
  final String? specialInstructions;
  final BookingMoney customerPayment;
  final BookingMoney companyCommission;
  final BookingCapabilities capabilities;
  final bool nameSignRequested;

  bool get canAccept => summary.canAccept;

  BookingDetail copyWithSummary(BookingSummary summary) => BookingDetail(
    summary: summary,
    passengers: passengers,
    luggage: luggage,
    flight: flight,
    specialInstructions: specialInstructions,
    customerPayment: customerPayment,
    companyCommission: companyCommission,
    capabilities: capabilities,
    nameSignRequested: nameSignRequested,
  );
}

class BookingAcceptance {
  const BookingAcceptance({
    required this.bookingNumber,
    required this.bookingStatus,
    required this.assignmentStatus,
    required this.acceptedAt,
    required this.idempotent,
  });

  factory BookingAcceptance.fromEnvelope(Map<String, dynamic> envelope) {
    final data = envelope['data'];
    if (envelope['success'] != true || data is! Map<String, dynamic>) {
      throw const ApiException(ApiFailureKind.invalidResponse);
    }
    final bookingNumber = data['bookingNumber'];
    final bookingStatus = data['bookingStatus'];
    final assignmentStatus = data['assignmentStatus'];
    final idempotent = data['idempotent'];
    if (bookingNumber is! String ||
        !RegExp(r'^TX\d{12}$').hasMatch(bookingNumber) ||
        bookingStatus is! String ||
        assignmentStatus is! String ||
        idempotent is! bool) {
      throw const ApiException(ApiFailureKind.invalidResponse);
    }
    final acceptedAt = data['acceptedAt'];
    if (acceptedAt != null && acceptedAt is! String) {
      throw const ApiException(ApiFailureKind.invalidResponse);
    }
    return BookingAcceptance(
      bookingNumber: bookingNumber,
      bookingStatus: BookingStatus.parse(bookingStatus),
      assignmentStatus: AssignmentStatus.parse(assignmentStatus),
      acceptedAt: _optionalString(acceptedAt),
      idempotent: idempotent,
    );
  }

  final String bookingNumber;
  final BookingStatus bookingStatus;
  final AssignmentStatus assignmentStatus;
  final String? acceptedAt;
  final bool idempotent;
}

class BookingReleaseResult {
  const BookingReleaseResult({
    required this.bookingNumber,
    required this.released,
    required this.status,
    required this.reasonCode,
  });

  factory BookingReleaseResult.fromEnvelope(Map<String, dynamic> envelope) {
    final data = envelope['data'];
    if (envelope['success'] != true || data is! Map<String, dynamic>) {
      throw const ApiException(ApiFailureKind.invalidResponse);
    }
    final bookingNumber = data['bookingNumber'];
    final released = data['released'];
    final status = data['status'];
    final reasonCode = data['reasonCode'];
    if (bookingNumber is! String ||
        !RegExp(r'^TX\d{12}$').hasMatch(bookingNumber) ||
        released is! bool ||
        status is! String ||
        reasonCode is! String) {
      throw const ApiException(ApiFailureKind.invalidResponse);
    }
    return BookingReleaseResult(
      bookingNumber: bookingNumber,
      released: released,
      status: BookingStatus.parse(status),
      reasonCode: reasonCode,
    );
  }

  final String bookingNumber;
  final bool released;
  final BookingStatus status;
  final String reasonCode;
}

String formatMoney(BookingMoney money) {
  if (!money.isAvailable) return '금액 정보 없음';
  final amount = money.amount!;
  final fixed = amount % 1 == 0
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2);
  final parts = fixed.split('.');
  final digits = parts.first;
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(',');
    buffer.write(digits[index]);
  }
  final formatted = parts.length == 2 ? '$buffer.${parts[1]}' : '$buffer';
  final currency = money.currency!.toUpperCase();
  return currency == 'THB' ? 'THB $formatted' : '$formatted $currency';
}

String? _optionalString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _optionalInt(Object? value) => value is num ? value.toInt() : null;

double? _optionalDouble(Object? value) =>
    value is num ? value.toDouble() : null;

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return List.unmodifiable(value.whereType<String>());
}

bool _isServiceDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
  final parsed = DateTime.tryParse(value);
  return parsed != null &&
      parsed.year.toString().padLeft(4, '0') == value.substring(0, 4) &&
      parsed.month.toString().padLeft(2, '0') == value.substring(5, 7) &&
      parsed.day.toString().padLeft(2, '0') == value.substring(8, 10);
}

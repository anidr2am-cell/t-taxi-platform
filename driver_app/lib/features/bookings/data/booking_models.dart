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

class BookingSummary {
  const BookingSummary({
    required this.bookingNumber,
    required this.status,
    required this.pickupDate,
    required this.pickupTime,
    required this.origin,
    required this.destination,
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
      pickupDate: pickupDate,
      pickupTime: pickupTime,
      origin: origin,
      destination: destination,
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
  final String pickupDate;
  final String pickupTime;
  final String origin;
  final String destination;
  final int? passengerCount;
  final BookingType vehicleType;
  final String? customerDisplayName;
  final String? flightNumber;
  final BookingMoney driverExpectedIncome;
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
    );
  }

  final BookingSummary summary;
  final PassengerBreakdown passengers;
  final LuggageBreakdown luggage;
  final FlightInfo flight;
  final String? specialInstructions;
  final BookingMoney customerPayment;
  final BookingMoney companyCommission;
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

bool _isServiceDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
  final parsed = DateTime.tryParse(value);
  return parsed != null &&
      parsed.year.toString().padLeft(4, '0') == value.substring(0, 4) &&
      parsed.month.toString().padLeft(2, '0') == value.substring(5, 7) &&
      parsed.day.toString().padLeft(2, '0') == value.substring(8, 10);
}

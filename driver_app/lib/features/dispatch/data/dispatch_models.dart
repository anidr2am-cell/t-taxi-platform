import '../../../core/network/api_exception.dart';

class DriverCallEligibility {
  const DriverCallEligibility({
    required this.canReceiveCalls,
    required this.reasonCode,
  });

  factory DriverCallEligibility.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      return const DriverCallEligibility(
        canReceiveCalls: false,
        reasonCode: 'UNKNOWN_RESTRICTION',
      );
    }
    return DriverCallEligibility(
      canReceiveCalls: value['canReceiveCalls'] == true,
      reasonCode: _optionalString(value['reasonCode']) ?? 'UNKNOWN_RESTRICTION',
    );
  }

  final bool canReceiveCalls;
  final String reasonCode;
}

class DriverDispatchStatus {
  const DriverDispatchStatus({
    required this.driverId,
    required this.active,
    required this.online,
    required this.status,
    required this.hasActiveJob,
    required this.lastSeenAt,
    required this.callEligibility,
  });

  factory DriverDispatchStatus.fromEnvelope(Map<String, dynamic> envelope) {
    return DriverDispatchStatus.fromJson(_envelopeData(envelope));
  }

  factory DriverDispatchStatus.fromJson(Map<String, dynamic> json) {
    final driverId = json['driverId'];
    final status = json['status'];
    if (driverId is! num || status is! String) {
      throw const ApiException(ApiFailureKind.invalidResponse);
    }
    return DriverDispatchStatus(
      driverId: driverId.toInt(),
      active: json['active'] == true,
      online: json['online'] == true,
      status: status,
      hasActiveJob: json['hasActiveJob'] == true,
      lastSeenAt: _optionalString(json['lastSeenAt']),
      callEligibility: DriverCallEligibility.fromJson(json['callEligibility']),
    );
  }

  final int driverId;
  final bool active;
  final bool online;
  final String status;
  final bool hasActiveJob;
  final String? lastSeenAt;
  final DriverCallEligibility callEligibility;
}

class CompatibleVehicle {
  const CompatibleVehicle({
    required this.driverVehicleId,
    required this.vehicleTypeCode,
    required this.vehicleTypeName,
    required this.plateNumber,
    required this.isExactMatch,
  });

  factory CompatibleVehicle.fromJson(Map<String, dynamic> json) {
    final id = json['driverVehicleId'];
    if (id is! num || id.toInt() <= 0) {
      throw const ApiException(ApiFailureKind.invalidResponse);
    }
    return CompatibleVehicle(
      driverVehicleId: id.toInt(),
      vehicleTypeCode: _optionalString(json['vehicleTypeCode']) ?? '',
      vehicleTypeName: _optionalString(json['vehicleTypeName']) ?? '',
      plateNumber: _optionalString(json['plateNumber']) ?? '',
      isExactMatch: json['isExactMatch'] == true,
    );
  }

  final int driverVehicleId;
  final String vehicleTypeCode;
  final String vehicleTypeName;
  final String plateNumber;
  final bool isExactMatch;

  String get displayName {
    final type = vehicleTypeName.isNotEmpty ? vehicleTypeName : vehicleTypeCode;
    return plateNumber.isEmpty ? type : '$type · $plateNumber';
  }
}

class OpenCall {
  const OpenCall({
    required this.bookingNumber,
    required this.status,
    required this.scheduledPickupAt,
    required this.pickupDate,
    required this.pickupTime,
    required this.origin,
    required this.destination,
    required this.serviceTypeCode,
    required this.serviceTypeName,
    required this.nameSignRequested,
    required this.nameSignText,
    required this.vehicleTypeCode,
    required this.vehicleTypeName,
    required this.vehicleMatchType,
    required this.isExactVehicleMatch,
    required this.compatibleVehicles,
    required this.passengerCount,
    required this.amount,
    required this.currency,
    required this.customerPaymentAmount,
    required this.customerPaymentCurrency,
    required this.customerPaymentMethod,
    required this.companyCommissionAmount,
    required this.companyCommissionCurrency,
    required this.driverExpectedIncomeAmount,
    required this.driverExpectedIncomeCurrency,
    required this.luggage,
    required this.isUrgentRequest,
    required this.negotiationId,
    required this.minRequiredEtaMinutes,
  });

  factory OpenCall.fromJson(Map<String, dynamic> json) {
    final bookingNumber = json['bookingNumber'];
    final status = json['status'];
    final origin = json['origin'];
    final destination = json['destination'];
    final matchType = json['vehicleMatchType'];
    final vehicles = json['compatibleVehicles'];
    if (bookingNumber is! String ||
        !RegExp(r'^TX\d{12}$').hasMatch(bookingNumber) ||
        status is! String ||
        origin is! String ||
        destination is! String ||
        matchType is! String ||
        vehicles is! List) {
      throw const ApiException(ApiFailureKind.invalidResponse);
    }
    final serviceType = _map(json['serviceType']);
    final vehicleType = _map(json['vehicleType']);
    return OpenCall(
      bookingNumber: bookingNumber,
      status: status,
      scheduledPickupAt: _optionalString(json['scheduledPickupAt']),
      pickupDate: _optionalString(json['pickupDate']) ?? '',
      pickupTime: _optionalString(json['pickupTime']) ?? '',
      origin: origin,
      destination: destination,
      serviceTypeCode: _optionalString(serviceType['code']) ?? '',
      serviceTypeName: _optionalString(serviceType['name']) ?? '',
      nameSignRequested: json['nameSignRequested'] == true,
      nameSignText: _optionalString(json['nameSignText']),
      vehicleTypeCode: _optionalString(vehicleType['code']) ?? '',
      vehicleTypeName: _optionalString(vehicleType['name']) ?? '',
      vehicleMatchType: matchType,
      isExactVehicleMatch: json['isExactVehicleMatch'] == true,
      compatibleVehicles: List.unmodifiable(
        vehicles.map((item) {
          if (item is! Map) {
            throw const ApiException(ApiFailureKind.invalidResponse);
          }
          return CompatibleVehicle.fromJson(Map<String, dynamic>.from(item));
        }),
      ),
      passengerCount: _number(json['passengerCount']).toInt(),
      amount: _number(json['amount']),
      currency: _optionalString(json['currency']) ?? '',
      customerPaymentAmount: _optionalNumber(json['customerPaymentAmount']),
      customerPaymentCurrency: _optionalString(json['customerPaymentCurrency']),
      customerPaymentMethod: _optionalString(json['customerPaymentMethod']),
      companyCommissionAmount: _optionalNumber(json['companyCommissionAmount']),
      companyCommissionCurrency: _optionalString(
        json['companyCommissionCurrency'],
      ),
      driverExpectedIncomeAmount: _optionalNumber(
        json['driverExpectedIncomeAmount'],
      ),
      driverExpectedIncomeCurrency: _optionalString(
        json['driverExpectedIncomeCurrency'],
      ),
      luggage: OpenCallLuggage.fromJson(json['luggage']),
      isUrgentRequest: json['isUrgentRequest'] == true,
      negotiationId: _optionalInt(json['negotiationId']),
      minRequiredEtaMinutes: _optionalInt(json['minRequiredEtaMinutes']),
    );
  }

  final String bookingNumber;
  final String status;
  final String? scheduledPickupAt;
  final String pickupDate;
  final String pickupTime;
  final String origin;
  final String destination;
  final String serviceTypeCode;
  final String serviceTypeName;
  final bool nameSignRequested;
  final String? nameSignText;
  final String vehicleTypeCode;
  final String vehicleTypeName;
  final String vehicleMatchType;
  final bool isExactVehicleMatch;
  final List<CompatibleVehicle> compatibleVehicles;
  final int passengerCount;
  final num amount;
  final String currency;
  final num? customerPaymentAmount;
  final String? customerPaymentCurrency;
  final String? customerPaymentMethod;
  final num? companyCommissionAmount;
  final String? companyCommissionCurrency;
  final num? driverExpectedIncomeAmount;
  final String? driverExpectedIncomeCurrency;
  final OpenCallLuggage luggage;
  final bool isUrgentRequest;
  final int? negotiationId;
  final int? minRequiredEtaMinutes;
}

class OpenCallLuggage {
  const OpenCallLuggage({
    required this.carriers20Inch,
    required this.carriers24InchPlus,
    required this.golfBags,
    required this.specialItems,
  });

  factory OpenCallLuggage.fromJson(Object? value) {
    final json = _map(value);
    return OpenCallLuggage(
      carriers20Inch: _number(json['carriers20Inch']).toInt(),
      carriers24InchPlus: _number(json['carriers24InchPlus']).toInt(),
      golfBags: _number(json['golfBags']).toInt(),
      specialItems: _optionalString(json['specialItems']),
    );
  }

  final int carriers20Inch;
  final int carriers24InchPlus;
  final int golfBags;
  final String? specialItems;
}

class OpenCallList {
  const OpenCallList({
    required this.items,
    required this.blockedReason,
    required this.message,
  });

  factory OpenCallList.fromEnvelope(Map<String, dynamic> envelope) {
    final data = _envelopeData(envelope);
    final items = data['items'];
    if (items is! List) {
      throw const ApiException(ApiFailureKind.invalidResponse);
    }
    return OpenCallList(
      items: List.unmodifiable(
        items.map((item) {
          if (item is! Map) {
            throw const ApiException(ApiFailureKind.invalidResponse);
          }
          return OpenCall.fromJson(Map<String, dynamic>.from(item));
        }),
      ),
      blockedReason: _optionalString(data['blockedReason']),
      message: _optionalString(data['message']),
    );
  }

  final List<OpenCall> items;
  final String? blockedReason;
  final String? message;
}

class ClaimResult {
  const ClaimResult({
    required this.bookingNumber,
    required this.status,
    required this.booking,
  });

  factory ClaimResult.fromEnvelope(Map<String, dynamic> envelope) {
    final data = _envelopeData(envelope);
    final bookingNumber = data['bookingNumber'];
    final status = data['status'];
    final booking = data['booking'];
    if (bookingNumber is! String ||
        !RegExp(r'^TX\d{12}$').hasMatch(bookingNumber) ||
        status is! String ||
        booking is! Map) {
      throw const ApiException(ApiFailureKind.invalidResponse);
    }
    return ClaimResult(
      bookingNumber: bookingNumber,
      status: status,
      booking: Map.unmodifiable(Map<String, dynamic>.from(booking)),
    );
  }

  final String bookingNumber;
  final String status;
  final Map<String, dynamic> booking;
}

class UrgentCallLockResult {
  const UrgentCallLockResult({
    required this.bookingNumber,
    required this.negotiationId,
    required this.attemptId,
    required this.attemptNumber,
    required this.driverId,
    required this.status,
    required this.lockExpiresAt,
  });

  factory UrgentCallLockResult.fromEnvelope(Map<String, dynamic> envelope) {
    final data = _envelopeData(envelope);
    return UrgentCallLockResult(
      bookingNumber: _requiredBookingNumber(data['bookingNumber']),
      negotiationId: _requiredPositiveInt(data['negotiationId']),
      attemptId: _requiredPositiveInt(data['attemptId']),
      attemptNumber: _requiredPositiveInt(data['attemptNumber']),
      driverId: _requiredPositiveInt(data['driverId']),
      status: _requiredString(data['status']),
      lockExpiresAt: _optionalString(data['lockExpiresAt']),
    );
  }

  final String bookingNumber;
  final int negotiationId;
  final int attemptId;
  final int attemptNumber;
  final int driverId;
  final String status;
  final String? lockExpiresAt;
}

class UrgentCallEtaResult {
  const UrgentCallEtaResult({
    required this.bookingNumber,
    required this.negotiationId,
    required this.attemptNumber,
    required this.driverId,
    required this.status,
    required this.etaMinutes,
    required this.customerDecisionExpiresAt,
  });

  factory UrgentCallEtaResult.fromEnvelope(Map<String, dynamic> envelope) {
    final data = _envelopeData(envelope);
    return UrgentCallEtaResult(
      bookingNumber: _requiredBookingNumber(data['bookingNumber']),
      negotiationId: _requiredPositiveInt(data['negotiationId']),
      attemptNumber: _requiredPositiveInt(data['attemptNumber']),
      driverId: _requiredPositiveInt(data['driverId']),
      status: _requiredString(data['status']),
      etaMinutes: _requiredPositiveInt(data['etaMinutes']),
      customerDecisionExpiresAt: _optionalString(
        data['customerDecisionExpiresAt'],
      ),
    );
  }

  final String bookingNumber;
  final int negotiationId;
  final int attemptNumber;
  final int driverId;
  final String status;
  final int etaMinutes;
  final String? customerDecisionExpiresAt;
}

Map<String, dynamic> _envelopeData(Map<String, dynamic> envelope) {
  final data = envelope['data'];
  if (envelope['success'] != true || data is! Map) {
    throw const ApiException(ApiFailureKind.invalidResponse);
  }
  return Map<String, dynamic>.from(data);
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

String? _optionalString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

num _number(Object? value) => value is num ? value : 0;

num? _optionalNumber(Object? value) => value is num ? value : null;

int? _optionalInt(Object? value) => value is num ? value.toInt() : null;

int _requiredPositiveInt(Object? value) {
  if (value is! num || value.toInt() <= 0) {
    throw const ApiException(ApiFailureKind.invalidResponse);
  }
  return value.toInt();
}

String _requiredString(Object? value) {
  final result = _optionalString(value);
  if (result == null) {
    throw const ApiException(ApiFailureKind.invalidResponse);
  }
  return result;
}

String _requiredBookingNumber(Object? value) {
  final result = _requiredString(value);
  if (!RegExp(r'^TX\d{12}$').hasMatch(result)) {
    throw const ApiException(ApiFailureKind.invalidResponse);
  }
  return result;
}

class DriverBooking {
  const DriverBooking({
    required this.bookingNumber,
    required this.status,
    required this.serviceTypeName,
    required this.pickupDate,
    required this.pickupTime,
    required this.origin,
    required this.destination,
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
  });

  final String bookingNumber;
  final String status;
  final String serviceTypeName;
  final String pickupDate;
  final String pickupTime;
  final String origin;
  final String destination;
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

  factory DriverBooking.fromJson(Map<String, dynamic> json) {
    final serviceType = Map<String, dynamic>.from(
      json['serviceType'] as Map? ?? {},
    );
    final vehicleType = Map<String, dynamic>.from(
      json['vehicleType'] as Map? ?? {},
    );
    return DriverBooking(
      bookingNumber: json['bookingNumber'] as String? ?? '',
      status: json['status'] as String? ?? '',
      serviceTypeName:
          serviceType['name'] as String? ??
          serviceType['code'] as String? ??
          '',
      pickupDate: json['pickupDate'] as String? ?? '',
      pickupTime: json['pickupTime'] as String? ?? '',
      origin: json['origin'] as String? ?? '',
      destination: json['destination'] as String? ?? '',
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
    );
  }
}

class DriverOpenCalls {
  const DriverOpenCalls({required this.items});

  final List<DriverOpenCall> items;

  factory DriverOpenCalls.fromJson(Map<String, dynamic> json) {
    return DriverOpenCalls(
      items: (json['items'] as List? ?? [])
          .map(
            (item) =>
                DriverOpenCall.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
    );
  }
}

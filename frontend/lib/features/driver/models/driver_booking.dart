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
    this.paymentMethod,
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
  final String? paymentMethod;
  final List<String> allowedActions;

  factory DriverBooking.fromJson(Map<String, dynamic> json) {
    final serviceType = Map<String, dynamic>.from(json['serviceType'] as Map? ?? {});
    final vehicleType = Map<String, dynamic>.from(json['vehicleType'] as Map? ?? {});
    return DriverBooking(
      bookingNumber: json['bookingNumber'] as String? ?? '',
      status: json['status'] as String? ?? '',
      serviceTypeName: serviceType['name'] as String? ?? serviceType['code'] as String? ?? '',
      pickupDate: json['pickupDate'] as String? ?? '',
      pickupTime: json['pickupTime'] as String? ?? '',
      origin: json['origin'] as String? ?? '',
      destination: json['destination'] as String? ?? '',
      passengerCount: json['passengerCount'] as int? ?? 0,
      vehicleTypeName: vehicleType['name'] as String? ?? vehicleType['code'] as String? ?? '',
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
      paymentMethod: json['paymentMethod'] as String?,
      allowedActions: (json['allowedActions'] as List? ?? [])
          .map((item) => item.toString())
          .toList(),
    );
  }
}

class DriverJobsToday {
  const DriverJobsToday({
    required this.date,
    required this.items,
  });

  final String date;
  final List<DriverBooking> items;

  factory DriverJobsToday.fromJson(Map<String, dynamic> json) {
    return DriverJobsToday(
      date: json['date'] as String? ?? '',
      items: (json['items'] as List? ?? [])
          .map((item) => DriverBooking.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
    );
  }
}

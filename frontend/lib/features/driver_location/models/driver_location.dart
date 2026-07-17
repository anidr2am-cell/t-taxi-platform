class DriverLocation {
  const DriverLocation({
    required this.driverId,
    required this.displayName,
    this.vehicle,
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.heading,
    this.speedKph,
    this.recordedAt,
    this.lastSeenAt,
    this.online,
    required this.stale,
    this.activeBooking,
  });

  final int driverId;
  final String displayName;
  final String? vehicle;
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final double? heading;
  final double? speedKph;
  final String? recordedAt;
  final String? lastSeenAt;
  final bool? online;
  final bool stale;
  final ActiveDriverBooking? activeBooking;

  factory DriverLocation.fromJson(Map<String, dynamic> json) {
    final booking = json['activeBooking'] is Map
        ? ActiveDriverBooking.fromJson(
            Map<String, dynamic>.from(json['activeBooking'] as Map),
          )
        : null;
    return DriverLocation(
      driverId: json['driverId'] as int? ?? 0,
      displayName: json['displayName'] as String? ?? 'Driver',
      vehicle: json['vehicle'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      accuracyMeters: (json['accuracyMeters'] as num?)?.toDouble(),
      heading: (json['heading'] as num?)?.toDouble(),
      speedKph: (json['speedKph'] as num?)?.toDouble(),
      recordedAt: json['recordedAt'] as String?,
      lastSeenAt: json['lastSeenAt'] as String?,
      online: json['online'] as bool?,
      stale: json['stale'] == true,
      activeBooking: booking,
    );
  }
}

class ActiveDriverBooking {
  const ActiveDriverBooking({
    required this.bookingNumber,
    required this.status,
  });

  final String bookingNumber;
  final String status;

  factory ActiveDriverBooking.fromJson(Map<String, dynamic> json) {
    return ActiveDriverBooking(
      bookingNumber: json['bookingNumber'] as String? ?? '',
      status: json['status'] as String? ?? '',
    );
  }
}

class GuestDriverLocationResult {
  const GuestDriverLocationResult({
    required this.available,
    this.bookingNumber,
    this.bookingStatus,
    this.reason,
    this.driver,
  });

  final bool available;
  final String? bookingNumber;
  final String? bookingStatus;
  final String? reason;
  final DriverLocation? driver;

  factory GuestDriverLocationResult.fromJson(Map<String, dynamic> json) {
    return GuestDriverLocationResult(
      available: json['available'] == true,
      bookingNumber: json['bookingNumber'] as String?,
      bookingStatus: json['bookingStatus'] as String?,
      reason: json['reason'] as String?,
      driver: json['driver'] is Map
          ? DriverLocation.fromJson(
              Map<String, dynamic>.from(json['driver'] as Map),
            )
          : null,
    );
  }
}

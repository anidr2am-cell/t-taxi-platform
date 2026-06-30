class DriverStatus {
  const DriverStatus({
    required this.driverId,
    required this.active,
    required this.online,
    required this.status,
    required this.hasActiveJob,
    this.lastSeenAt,
  });

  final int driverId;
  final bool active;
  final bool online;
  final String status;
  final bool hasActiveJob;
  final String? lastSeenAt;

  factory DriverStatus.fromJson(Map<String, dynamic> json) {
    return DriverStatus(
      driverId: (json['driverId'] as num?)?.toInt() ?? 0,
      active: json['active'] as bool? ?? false,
      online: json['online'] as bool? ?? false,
      status: json['status'] as String? ?? 'OFFLINE',
      hasActiveJob: json['hasActiveJob'] as bool? ?? false,
      lastSeenAt: json['lastSeenAt'] as String?,
    );
  }
}

class DriverStatus {
  const DriverStatus({
    required this.driverId,
    required this.active,
    required this.online,
    required this.status,
    required this.hasActiveJob,
    this.lastSeenAt,
    this.callEligibility = const DriverCallEligibility(
      canReceiveCalls: false,
      reasonCode: DriverCallEligibilityReason.unknownRestriction,
    ),
  });

  final int driverId;
  final bool active;
  final bool online;
  final String status;
  final bool hasActiveJob;
  final String? lastSeenAt;
  final DriverCallEligibility callEligibility;

  factory DriverStatus.fromJson(Map<String, dynamic> json) {
    final rawEligibility = json['callEligibility'];
    return DriverStatus(
      driverId: (json['driverId'] as num?)?.toInt() ?? 0,
      active: json['active'] as bool? ?? false,
      online: json['online'] as bool? ?? false,
      status: json['status'] as String? ?? 'OFFLINE',
      hasActiveJob: json['hasActiveJob'] as bool? ?? false,
      lastSeenAt: json['lastSeenAt'] as String?,
      callEligibility: rawEligibility is Map
          ? DriverCallEligibility.fromJson(
              Map<String, dynamic>.from(rawEligibility),
            )
          : DriverCallEligibility.fallback(
              online: json['online'] as bool? ?? false,
              status: json['status'] as String? ?? 'OFFLINE',
              hasActiveJob: json['hasActiveJob'] as bool? ?? false,
            ),
    );
  }
}

class DriverCallEligibility {
  const DriverCallEligibility({
    required this.canReceiveCalls,
    required this.reasonCode,
  });

  final bool canReceiveCalls;
  final String reasonCode;

  factory DriverCallEligibility.fromJson(Map<String, dynamic> json) {
    return DriverCallEligibility(
      canReceiveCalls: json['canReceiveCalls'] as bool? ?? false,
      reasonCode:
          json['reasonCode'] as String? ??
          DriverCallEligibilityReason.unknownRestriction,
    );
  }

  factory DriverCallEligibility.fallback({
    required bool online,
    required String status,
    required bool hasActiveJob,
  }) {
    if (hasActiveJob) {
      return const DriverCallEligibility(
        canReceiveCalls: false,
        reasonCode: DriverCallEligibilityReason.activeTrip,
      );
    }
    if (!online || status == 'OFFLINE') {
      return const DriverCallEligibility(
        canReceiveCalls: false,
        reasonCode: DriverCallEligibilityReason.offline,
      );
    }
    if (status == 'AVAILABLE') {
      return const DriverCallEligibility(
        canReceiveCalls: true,
        reasonCode: DriverCallEligibilityReason.ready,
      );
    }
    return const DriverCallEligibility(
      canReceiveCalls: false,
      reasonCode: DriverCallEligibilityReason.unknownRestriction,
    );
  }
}

class DriverCallEligibilityReason {
  const DriverCallEligibilityReason._();

  static const ready = 'READY';
  static const offline = 'OFFLINE';
  static const activeTrip = 'ACTIVE_TRIP';
  static const unpaidSettlement = 'UNPAID_SETTLEMENT';
  static const customerComplaintReview = 'CUSTOMER_COMPLAINT_REVIEW';
  static const accountUnderReview = 'ACCOUNT_UNDER_REVIEW';
  static const accountRestricted = 'ACCOUNT_RESTRICTED';
  static const driverApprovalPending = 'DRIVER_APPROVAL_PENDING';
  static const vehicleReviewRequired = 'VEHICLE_REVIEW_REQUIRED';
  static const unknownRestriction = 'UNKNOWN_RESTRICTION';
}

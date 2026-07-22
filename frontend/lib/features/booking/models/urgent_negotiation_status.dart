class UrgentNegotiationStatus {
  const UrgentNegotiationStatus({
    required this.bookingNumber,
    this.bookingId,
    required this.bookingStatus,
    required this.negotiationId,
    required this.status,
    required this.attemptCount,
    this.minRequiredEtaMinutes,
    this.proposedEtaMinutes,
    this.customerDecisionExpiresAt,
    this.closedReason,
  });

  final String bookingNumber;
  final int? bookingId;
  final String bookingStatus;
  final int negotiationId;
  final String status;
  final int attemptCount;
  final int? minRequiredEtaMinutes;
  final int? proposedEtaMinutes;
  final String? customerDecisionExpiresAt;
  final String? closedReason;

  bool get isAwaitingCustomer => status == 'AWAITING_CUSTOMER';
  bool get isBroadcasting => status == 'BROADCASTING';
  bool get isConfirmed => status == 'CONFIRMED';
  bool get isCancelled => status == 'CANCELLED';

  factory UrgentNegotiationStatus.fromJson(Map<String, dynamic> json) {
    return UrgentNegotiationStatus(
      bookingNumber: json['bookingNumber'] as String? ?? '',
      bookingId: json['bookingId'] as int?,
      bookingStatus: json['bookingStatus'] as String? ?? 'OPEN',
      negotiationId: json['negotiationId'] as int? ?? 0,
      status: json['status'] as String? ?? 'BROADCASTING',
      attemptCount: json['attemptCount'] as int? ?? 0,
      minRequiredEtaMinutes: json['minRequiredEtaMinutes'] as int?,
      proposedEtaMinutes: json['proposedEtaMinutes'] as int?,
      customerDecisionExpiresAt: json['customerDecisionExpiresAt'] as String?,
      closedReason: json['closedReason'] as String?,
    );
  }
}

class UrgentDecisionResult {
  const UrgentDecisionResult({
    required this.bookingNumber,
    required this.decision,
    required this.status,
    this.bookingStatus,
    this.etaMinutes,
    this.attemptCount,
    this.closedReason,
    this.assignmentId,
  });

  final String bookingNumber;
  final String decision;
  final String status;
  final String? bookingStatus;
  final int? etaMinutes;
  final int? attemptCount;
  final String? closedReason;
  final int? assignmentId;

  factory UrgentDecisionResult.fromJson(Map<String, dynamic> json) {
    return UrgentDecisionResult(
      bookingNumber: json['bookingNumber'] as String? ?? '',
      decision: json['decision'] as String? ?? '',
      status: json['status'] as String? ?? '',
      bookingStatus: json['bookingStatus'] as String?,
      etaMinutes: json['etaMinutes'] as int?,
      attemptCount: json['attemptCount'] as int?,
      closedReason: json['closedReason'] as String?,
      assignmentId: json['assignmentId'] as int?,
    );
  }
}

class BookingCreateResult {
  final int? bookingId;
  final String bookingNumber;
  final String status;
  final String paymentMethod;
  final String paymentStatus;
  final num totalAmount;
  final String currency;
  final String? guestAccessToken;
  final String chatRoomCode;
  final String boardingQrToken;
  final String trustMessage;

  const BookingCreateResult({
    this.bookingId,
    required this.bookingNumber,
    required this.status,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.totalAmount,
    required this.currency,
    this.guestAccessToken,
    required this.chatRoomCode,
    required this.boardingQrToken,
    required this.trustMessage,
  });

  factory BookingCreateResult.fromJson(Map<String, dynamic> json) {
    return BookingCreateResult(
      bookingId: json['bookingId'] as int?,
      bookingNumber: json['bookingNumber'] as String? ?? '',
      status: json['status'] as String? ?? 'PENDING',
      paymentMethod: json['paymentMethod'] as String? ?? 'PAY_DRIVER',
      paymentStatus: json['paymentStatus'] as String? ?? 'UNPAID',
      totalAmount: json['totalAmount'] as num? ?? 0,
      currency: json['currency'] as String? ?? 'THB',
      guestAccessToken: json['guestAccessToken'] as String?,
      chatRoomCode: json['chatRoomCode'] as String? ?? '',
      boardingQrToken: json['boardingQrToken'] as String? ?? '',
      trustMessage: json['trustMessage'] as String? ?? '',
    );
  }
}

class DropoffQrIssueResult {
  final String bookingNumber;
  final String status;
  final String dropoffQrToken;
  final String dropoffQrExpiresAt;

  const DropoffQrIssueResult({
    required this.bookingNumber,
    required this.status,
    required this.dropoffQrToken,
    required this.dropoffQrExpiresAt,
  });

  factory DropoffQrIssueResult.fromJson(Map<String, dynamic> json) {
    return DropoffQrIssueResult(
      bookingNumber: json['bookingNumber'] as String? ?? '',
      status: json['status'] as String? ?? '',
      dropoffQrToken: json['dropoffQrToken'] as String? ?? '',
      dropoffQrExpiresAt: json['dropoffQrExpiresAt'] as String? ?? '',
    );
  }
}

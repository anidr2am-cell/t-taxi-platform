import '../../../core/network/api_exception.dart';

enum SettlementStatusCode {
  notDueYet,
  due,
  receiptSubmitted,
  overdue,
  rejected,
  approved,
  waived,
  unknown,
}

class SettlementStatus {
  const SettlementStatus(this.raw, this.code);

  factory SettlementStatus.parse(Object? value) {
    final raw = value is String ? value.trim() : '';
    final code = switch (raw) {
      'NOT_DUE_YET' => SettlementStatusCode.notDueYet,
      'DUE' => SettlementStatusCode.due,
      'RECEIPT_SUBMITTED' => SettlementStatusCode.receiptSubmitted,
      'OVERDUE' => SettlementStatusCode.overdue,
      'REJECTED' => SettlementStatusCode.rejected,
      'APPROVED' || 'PAID' => SettlementStatusCode.approved,
      'WAIVED' => SettlementStatusCode.waived,
      _ => SettlementStatusCode.unknown,
    };
    return SettlementStatus(raw, code);
  }

  final String raw;
  final SettlementStatusCode code;

  bool get countsAsPending => switch (code) {
    SettlementStatusCode.due ||
    SettlementStatusCode.receiptSubmitted ||
    SettlementStatusCode.overdue ||
    SettlementStatusCode.rejected ||
    SettlementStatusCode.unknown => true,
    SettlementStatusCode.notDueYet ||
    SettlementStatusCode.approved ||
    SettlementStatusCode.waived => false,
  };

  bool get canUpload => switch (code) {
    SettlementStatusCode.due ||
    SettlementStatusCode.overdue ||
    SettlementStatusCode.rejected => true,
    _ => false,
  };

  String get label => switch (code) {
    SettlementStatusCode.notDueYet => '정산 대상 아님',
    SettlementStatusCode.due => '송금 필요',
    SettlementStatusCode.receiptSubmitted => '승인 대기 중',
    SettlementStatusCode.overdue => '기한 초과',
    SettlementStatusCode.rejected => '반려됨',
    SettlementStatusCode.approved => '정산 완료',
    SettlementStatusCode.waived => '면제',
    SettlementStatusCode.unknown => '상태 확인 필요',
  };
}

class PaymentInstructions {
  const PaymentInstructions({
    required this.bankName,
    required this.accountName,
    required this.accountNumber,
    required this.promptPayNumber,
    required this.promptPayQrImageUrl,
  });

  factory PaymentInstructions.fromJson(Object? value) {
    if (value is! Map) return const PaymentInstructions.empty();
    final json = Map<String, dynamic>.from(value);
    return PaymentInstructions(
      bankName: _optionalString(json['bankName']) ?? '',
      accountName: _optionalString(json['accountName']) ?? '',
      accountNumber: _optionalString(json['accountNumber']) ?? '',
      promptPayNumber: _optionalString(json['promptPayNumber']) ?? '',
      promptPayQrImageUrl: _optionalString(json['promptPayQrImageUrl']) ?? '',
    );
  }

  const PaymentInstructions.empty()
    : bankName = '',
      accountName = '',
      accountNumber = '',
      promptPayNumber = '',
      promptPayQrImageUrl = '';

  final String bankName;
  final String accountName;
  final String accountNumber;
  final String promptPayNumber;
  final String promptPayQrImageUrl;

  bool get hasAny =>
      bankName.isNotEmpty ||
      accountName.isNotEmpty ||
      accountNumber.isNotEmpty ||
      promptPayNumber.isNotEmpty ||
      promptPayQrImageUrl.isNotEmpty;
}

class SettlementItem {
  const SettlementItem({
    required this.bookingNumber,
    required this.status,
    required this.pickupDate,
    required this.pickupTime,
    required this.origin,
    required this.destination,
    required this.completedAt,
    required this.commissionAmount,
    required this.customerPaymentAmount,
    required this.customerPaymentCurrency,
    required this.customerTotalAmount,
    required this.customerTotalCurrency,
    required this.companyCommissionAmount,
    required this.companyCommissionCurrency,
    required this.nameSignAmount,
    required this.driverExpectedIncomeAmount,
    required this.driverExpectedIncomeCurrency,
    required this.currency,
    required this.commissionStatus,
    required this.blocksNewCalls,
    required this.dueAt,
    required this.receiptStatus,
    required this.receiptSubmittedAt,
    required this.receiptUploadedAt,
    required this.rejectionReason,
    required this.approvalMode,
    required this.approvalNote,
    required this.approvedByUserId,
    required this.approvalRecordedAt,
    required this.receiptMissingAtApproval,
    required this.receiptFileId,
    required this.receiptUrl,
    required this.paymentInstructions,
  });

  factory SettlementItem.fromJson(Map<String, dynamic> json) {
    final bookingNumber = json['bookingNumber'];
    if (bookingNumber is! String || bookingNumber.isEmpty) {
      throw const ApiException(ApiFailureKind.invalidResponse);
    }
    return SettlementItem(
      bookingNumber: bookingNumber,
      status: _optionalString(json['status']),
      pickupDate: _optionalString(json['pickupDate']),
      pickupTime: _optionalString(json['pickupTime']),
      origin: _optionalString(json['origin']),
      destination: _optionalString(json['destination']),
      completedAt: _optionalString(json['completedAt']),
      commissionAmount: _optionalNum(json['commissionAmount']),
      customerPaymentAmount: _optionalNum(json['customerPaymentAmount']),
      customerPaymentCurrency: _optionalString(json['customerPaymentCurrency']),
      customerTotalAmount: _optionalNum(json['customerTotalAmount']),
      customerTotalCurrency: _optionalString(json['customerTotalCurrency']),
      companyCommissionAmount: _optionalNum(json['companyCommissionAmount']),
      companyCommissionCurrency: _optionalString(
        json['companyCommissionCurrency'],
      ),
      nameSignAmount: _optionalNum(json['nameSignAmount']),
      driverExpectedIncomeAmount: _optionalNum(
        json['driverExpectedIncomeAmount'],
      ),
      driverExpectedIncomeCurrency: _optionalString(
        json['driverExpectedIncomeCurrency'],
      ),
      currency: _optionalString(json['currency']),
      commissionStatus: SettlementStatus.parse(json['commissionStatus']),
      blocksNewCalls: json['blocksNewCalls'] == true,
      dueAt: _optionalString(json['dueAt']),
      receiptStatus: _optionalString(json['receiptStatus']),
      receiptSubmittedAt: _optionalString(json['receiptSubmittedAt']),
      receiptUploadedAt: _optionalString(json['receiptUploadedAt']),
      rejectionReason: _optionalString(json['rejectionReason']),
      approvalMode: _optionalString(json['approvalMode']),
      approvalNote: _optionalString(json['approvalNote']),
      approvedByUserId: _optionalInt(json['approvedByUserId']),
      approvalRecordedAt: _optionalString(json['approvalRecordedAt']),
      receiptMissingAtApproval: json['receiptMissingAtApproval'] == true,
      receiptFileId: _optionalInt(json['receiptFileId']),
      receiptUrl: _optionalString(json['receiptUrl']),
      paymentInstructions: PaymentInstructions.fromJson(
        json['paymentInstructions'],
      ),
    );
  }

  final String bookingNumber;
  final String? status;
  final String? pickupDate;
  final String? pickupTime;
  final String? origin;
  final String? destination;
  final String? completedAt;
  final num? commissionAmount;
  final num? customerPaymentAmount;
  final String? customerPaymentCurrency;
  final num? customerTotalAmount;
  final String? customerTotalCurrency;
  final num? companyCommissionAmount;
  final String? companyCommissionCurrency;
  final num? nameSignAmount;
  final num? driverExpectedIncomeAmount;
  final String? driverExpectedIncomeCurrency;
  final String? currency;
  final SettlementStatus commissionStatus;
  final bool blocksNewCalls;
  final String? dueAt;
  final String? receiptStatus;
  final String? receiptSubmittedAt;
  final String? receiptUploadedAt;
  final String? rejectionReason;
  final String? approvalMode;
  final String? approvalNote;
  final int? approvedByUserId;
  final String? approvalRecordedAt;
  final bool receiptMissingAtApproval;
  final int? receiptFileId;
  final String? receiptUrl;
  final PaymentInstructions paymentInstructions;

  bool get countsForBadge => blocksNewCalls || commissionStatus.countsAsPending;
  bool get canUploadReceipt => commissionStatus.canUpload;
  bool get hasReceipt => receiptUrl != null || receiptFileId != null;
}

class SettlementUploadFile {
  const SettlementUploadFile({required this.filename, required this.bytes});

  final String filename;
  final List<int> bytes;
}

String formatSettlementMoney(num? amount, String? currency) {
  if (amount == null) return '금액 정보 없음';
  final fixed = amount % 1 == 0
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2);
  final parts = fixed.split('.');
  final digits = parts.first;
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  final value = parts.length == 2 ? '$buffer.${parts[1]}' : '$buffer';
  final unit = (currency ?? '').toUpperCase();
  return unit.isEmpty ? value : '$unit $value';
}

String? _optionalString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

num? _optionalNum(Object? value) => value is num ? value : null;
int? _optionalInt(Object? value) => value is num ? value.toInt() : null;

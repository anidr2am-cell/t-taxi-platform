import 'booking_create_result.dart';
import 'booking_contact_connect_args.dart';

enum ContactCompletionTarget {
  lookup,
  urgentFlow,
  completePage,
}

ContactCompletionTarget resolveContactCompletionTarget({
  BookingContactConnectArgs? args,
  ContactConnectionState? connection,
  BookingCreateResult? result,
}) {
  if (result == null) return ContactCompletionTarget.lookup;
  final isUrgent = args?.isUrgent ??
      connection?.isUrgentRequest ??
      result.isUrgentRequest;
  return isUrgent
      ? ContactCompletionTarget.urgentFlow
      : ContactCompletionTarget.completePage;
}

class ContactChannel {
  const ContactChannel({
    required this.code,
    required this.displayName,
    this.addUrl,
    this.accountId,
    this.phoneNumber,
    this.qrImageUrl,
  });

  final String code;
  final String displayName;
  final String? addUrl;
  final String? accountId;
  final String? phoneNumber;
  final String? qrImageUrl;

  factory ContactChannel.fromJson(Map<String, dynamic> json) {
    return ContactChannel(
      code: json['code'] as String? ?? '',
      displayName: json['displayName'] as String? ?? json['code'] as String? ?? '',
      addUrl: json['addUrl'] as String?,
      accountId: json['accountId'] as String?,
      phoneNumber: json['phoneNumber'] as String?,
      qrImageUrl: json['qrImageUrl'] as String?,
    );
  }
}

class ContactConnectionState {
  const ContactConnectionState({
    required this.bookingNumber,
    required this.contactStatus,
    this.contactChannel,
    this.contactConnectionRequired = false,
    this.connectionChannel,
    this.connectionStatus,
    this.isUrgentRequest = false,
    this.bookingStatus,
    this.paymentMethod,
    this.paymentStatus,
    this.totalAmount,
    this.currency,
  });

  final String bookingNumber;
  final String contactStatus;
  final String? contactChannel;
  final bool contactConnectionRequired;
  final String? connectionChannel;
  final String? connectionStatus;
  final bool isUrgentRequest;
  final String? bookingStatus;
  final String? paymentMethod;
  final String? paymentStatus;
  final num? totalAmount;
  final String? currency;

  bool get isVerified => contactStatus == 'VERIFIED';

  bool get isConfirmRequested => contactStatus == 'CONFIRM_REQUESTED';

  bool get isPending => contactStatus == 'PENDING';

  factory ContactConnectionState.fromJson(Map<String, dynamic> json) {
    final connection = json['connection'] is Map
        ? Map<String, dynamic>.from(json['connection'] as Map)
        : null;
    return ContactConnectionState(
      bookingNumber: json['bookingNumber'] as String? ?? '',
      contactStatus: json['contactStatus'] as String? ?? 'PENDING',
      contactChannel: json['contactChannel'] as String?,
      contactConnectionRequired: json['contactConnectionRequired'] == true,
      connectionChannel: connection?['channel'] as String?,
      connectionStatus: connection?['status'] as String?,
      isUrgentRequest: json['isUrgentRequest'] == true,
      bookingStatus: json['bookingStatus'] as String?,
      paymentMethod: json['paymentMethod'] as String?,
      paymentStatus: json['paymentStatus'] as String?,
      totalAmount: json['totalAmount'] as num?,
      currency: json['currency'] as String?,
    );
  }

  BookingCreateResult toMinimalCreateResult({String? guestAccessToken}) {
    return BookingCreateResult(
      bookingNumber: bookingNumber,
      status: bookingStatus ?? 'OPEN',
      paymentMethod: paymentMethod ?? 'PAY_DRIVER',
      paymentStatus: paymentStatus ?? 'UNPAID',
      totalAmount: totalAmount ?? 0,
      currency: currency ?? 'THB',
      guestAccessToken: guestAccessToken,
      boardingQrToken: '',
      trustMessage: '',
      isUrgentRequest: isUrgentRequest,
      contactStatus: contactStatus,
      contactConnectionRequired: contactConnectionRequired,
    );
  }
}

/// Locale-ordered messenger channel codes (enabled channels only).
List<String> contactChannelOrderForLocale(String languageCode) {
  switch (languageCode) {
    case 'ko':
      return const ['KAKAO', 'LINE', 'WHATSAPP', 'WECHAT'];
    case 'th':
      return const ['LINE', 'WHATSAPP', 'WECHAT', 'KAKAO'];
    case 'zh':
      return const ['WECHAT', 'LINE', 'WHATSAPP', 'KAKAO'];
    default:
      return const ['WHATSAPP', 'LINE', 'WECHAT', 'KAKAO'];
  }
}

List<ContactChannel> orderContactChannels(
  List<ContactChannel> channels,
  String languageCode,
) {
  final order = contactChannelOrderForLocale(languageCode);
  final byCode = {for (final channel in channels) channel.code: channel};
  final ordered = <ContactChannel>[];
  for (final code in order) {
    final channel = byCode.remove(code);
    if (channel != null) ordered.add(channel);
  }
  ordered.addAll(byCode.values);
  return ordered;
}

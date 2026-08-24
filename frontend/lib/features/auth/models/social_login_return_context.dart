import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../booking/models/booking_create_result.dart';
import '../../booking/models/location_option.dart';
import '../config/kakao_auth_config.dart';

class SocialLoginReturnContext {
  const SocialLoginReturnContext({
    required this.redirectUri,
    required this.result,
    required this.serviceLabel,
    this.origin,
    this.destination,
    this.serviceTypeCode,
    this.originAirportCode,
    this.nameSignRequested = false,
    this.customerPhone,
    this.scheduledPickupAt,
    this.selectedVehicle,
    this.enableCustomerTools = false,
  });

  final String redirectUri;
  final BookingCreateResult result;
  final String serviceLabel;
  final LocationOption? origin;
  final LocationOption? destination;
  final String? serviceTypeCode;
  final String? originAirportCode;
  final bool nameSignRequested;
  final String? customerPhone;
  final String? scheduledPickupAt;
  final String? selectedVehicle;
  final bool enableCustomerTools;

  factory SocialLoginReturnContext.fromBookingComplete({
    required BookingCreateResult result,
    required String serviceLabel,
    LocationOption? origin,
    LocationOption? destination,
    String? serviceTypeCode,
    String? originAirportCode,
    bool nameSignRequested = false,
    String? customerPhone,
    String? scheduledPickupAt,
    String? selectedVehicle,
    bool enableCustomerTools = false,
    Uri? baseUri,
  }) {
    return SocialLoginReturnContext(
      redirectUri: KakaoAuthConfig.buildRedirectUri(base: baseUri),
      result: result,
      serviceLabel: serviceLabel,
      origin: origin,
      destination: destination,
      serviceTypeCode: serviceTypeCode,
      originAirportCode: originAirportCode,
      nameSignRequested: nameSignRequested,
      customerPhone: customerPhone,
      scheduledPickupAt: scheduledPickupAt,
      selectedVehicle: selectedVehicle,
      enableCustomerTools: enableCustomerTools,
    );
  }

  Map<String, dynamic> toJson() => {
    'redirectUri': redirectUri,
    'result': _resultToJson(result),
    'serviceLabel': serviceLabel,
    'origin': origin?.toJson(),
    'destination': destination?.toJson(),
    'serviceTypeCode': serviceTypeCode,
    'originAirportCode': originAirportCode,
    'nameSignRequested': nameSignRequested,
    'customerPhone': customerPhone,
    'scheduledPickupAt': scheduledPickupAt,
    'selectedVehicle': selectedVehicle,
    'enableCustomerTools': enableCustomerTools,
  };

  factory SocialLoginReturnContext.fromJson(Map<String, dynamic> json) {
    return SocialLoginReturnContext(
      redirectUri: json['redirectUri'] as String? ?? '',
      result: _resultFromJson(
        Map<String, dynamic>.from(json['result'] as Map? ?? const {}),
      ),
      serviceLabel: json['serviceLabel'] as String? ?? '',
      origin: json['origin'] is Map
          ? LocationOption.fromJson(
              Map<String, dynamic>.from(json['origin'] as Map),
            )
          : null,
      destination: json['destination'] is Map
          ? LocationOption.fromJson(
              Map<String, dynamic>.from(json['destination'] as Map),
            )
          : null,
      serviceTypeCode: json['serviceTypeCode'] as String?,
      originAirportCode: json['originAirportCode'] as String?,
      nameSignRequested: json['nameSignRequested'] == true,
      customerPhone: json['customerPhone'] as String?,
      scheduledPickupAt: json['scheduledPickupAt'] as String?,
      selectedVehicle: json['selectedVehicle'] as String?,
      enableCustomerTools: json['enableCustomerTools'] == true,
    );
  }

  static Map<String, dynamic> _resultToJson(BookingCreateResult result) => {
    'bookingId': result.bookingId,
    'bookingNumber': result.bookingNumber,
    'status': result.status,
    'paymentMethod': result.paymentMethod,
    'paymentStatus': result.paymentStatus,
    'totalAmount': result.totalAmount,
    'currency': result.currency,
    'guestAccessToken': result.guestAccessToken,
    'boardingQrToken': result.boardingQrToken,
    'trustMessage': result.trustMessage,
    'trackingAvailable': result.trackingAvailable,
    'canCancel': result.canCancel,
    'cancellationDeadline': result.cancellationDeadline,
    'cancellationBlockedReason': result.cancellationBlockedReason,
    'isUrgentRequest': result.isUrgentRequest,
    'contactStatus': result.contactStatus,
    'contactConnectionRequired': result.contactConnectionRequired,
  };

  static BookingCreateResult _resultFromJson(Map<String, dynamic> json) {
    return BookingCreateResult(
      bookingId: json['bookingId'] as int?,
      bookingNumber: json['bookingNumber'] as String? ?? '',
      status: json['status'] as String? ?? 'PENDING',
      paymentMethod: json['paymentMethod'] as String? ?? 'PAY_DRIVER',
      paymentStatus: json['paymentStatus'] as String? ?? 'UNPAID',
      totalAmount: json['totalAmount'] as num? ?? 0,
      currency: json['currency'] as String? ?? 'THB',
      guestAccessToken: json['guestAccessToken'] as String?,
      boardingQrToken: json['boardingQrToken'] as String? ?? '',
      trustMessage: json['trustMessage'] as String? ?? '',
      trackingAvailable: json['trackingAvailable'] == true,
      canCancel: json['canCancel'] == true,
      cancellationDeadline: json['cancellationDeadline'] as String?,
      cancellationBlockedReason: json['cancellationBlockedReason'] as String?,
      isUrgentRequest: json['isUrgentRequest'] == true,
      contactStatus: json['contactStatus'] as String?,
      contactConnectionRequired: json['contactConnectionRequired'] == true,
    );
  }
}

class SocialLoginReturnStorage {
  static const storageKey = 'social_login_return_context';

  Future<void> save(SocialLoginReturnContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(context.toJson()));
  }

  Future<SocialLoginReturnContext?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      return SocialLoginReturnContext.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  Future<SocialLoginReturnContext?> loadAndClear() async {
    final context = await load();
    await clear();
    return context;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
  }
}

String? parseKakaoAuthorizationCode(Uri uri) {
  final code = uri.queryParameters['code']?.trim();
  if (code == null || code.isEmpty) {
    return null;
  }
  return code;
}

String? parseKakaoAuthorizationError(Uri uri) {
  final error = uri.queryParameters['error']?.trim();
  if (error == null || error.isEmpty) {
    return null;
  }
  final description = uri.queryParameters['error_description']?.trim();
  if (description == null || description.isEmpty) {
    return error;
  }
  return '$error: $description';
}

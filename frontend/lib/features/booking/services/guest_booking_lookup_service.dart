import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_config.dart';
import '../models/guest_booking_lookup_result.dart';
import '../widgets/booking_review_form.dart';
import 'booking_api_service.dart';

class GuestBookingLookupService {
  GuestBookingLookupService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _client;
  final String _baseUrl;

  static const _cachedBookingKey = 'guest_lookup_booking';
  static String _boardingQrCacheKey(String bookingNumber) =>
      'guest_lookup_boarding_qr_${bookingNumber.trim().toUpperCase()}';

  String get _base => '$_baseUrl/api/v1';

  Future<GuestBookingLookupResult> lookup({
    required String bookingNumber,
    required String phone,
  }) async {
    final response = await _client.post(
      Uri.parse('$_base/public/bookings/lookup'),
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'bookingNumber': bookingNumber,
        'phone': phone,
      }),
    );
    final decoded = jsonDecode(response.body);

    if (response.statusCode >= 400) {
      final message = decoded is Map
          ? decoded['message'] as String? ?? 'Booking not found'
          : 'Booking not found';
      final code = decoded is Map ? decoded['error_code'] as String? : null;
      throw BookingApiException(message, code);
    }

    final result = GuestBookingLookupResult.fromJson(
      Map<String, dynamic>.from((decoded as Map)['data'] as Map),
    ).copyWith(customerPhone: phone.trim());
    await persist(result);
    return result;
  }

  Future<void> persistFromCreateSummary(GuestBookingLookupResult result) async {
    await persist(result);
  }

  Future<void> persist(GuestBookingLookupResult result) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cachedBookingKey, jsonEncode(result.toJson()));
    await BookingReviewApi().persistGuestToken(
      result.bookingNumber,
      result.guestAccessToken,
    );
  }

  Future<GuestBookingLookupResult?> loadCached() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cachedBookingKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final result = GuestBookingLookupResult.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      if (!result.hasValidGuestAccess) {
        await clearCached();
        return null;
      }
      return result;
    } catch (_) {
      await clearCached();
      return null;
    }
  }

  Future<void> clearCached() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = await loadCachedWithoutValidation();
    if (cached != null) {
      await BookingReviewApi().persistGuestToken(cached.bookingNumber, null);
      await clearBoardingQr(cached.bookingNumber);
    }
    await prefs.remove(_cachedBookingKey);
  }

  Future<void> persistBoardingQr({
    required String bookingNumber,
    required String token,
    required String expiresAt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _boardingQrCacheKey(bookingNumber),
      jsonEncode({
        'token': token,
        'expiresAt': expiresAt,
        'bookingNumber': bookingNumber.trim().toUpperCase(),
      }),
    );
  }

  Future<({String token, String expiresAt})?> loadBoardingQr(
    String bookingNumber,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_boardingQrCacheKey(bookingNumber));
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final token = map['token'] as String? ?? '';
      final expiresAt = map['expiresAt'] as String? ?? '';
      if (token.isEmpty || expiresAt.isEmpty) return null;
      return (token: token, expiresAt: expiresAt);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearBoardingQr(String bookingNumber) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_boardingQrCacheKey(bookingNumber));
  }

  Future<GuestBookingLookupResult?> loadCachedWithoutValidation() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cachedBookingKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return GuestBookingLookupResult.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  /// Cancels a guest booking via server policy. Final eligibility is always
  /// re-validated on the server; do not trust a prior `canCancel` snapshot.
  Future<GuestBookingLookupResult> cancelBooking({
    required GuestBookingLookupResult booking,
    String? reason,
  }) async {
    final token = booking.guestAccessToken.trim();
    if (token.isEmpty) {
      throw BookingApiException(
        'Guest access token is required',
        'BOOKING_NOT_ACCESSIBLE',
      );
    }

    final response = await _client.post(
      Uri.parse('$_base/bookings/${booking.bookingNumber}/cancel'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-Guest-Access-Token': token,
      },
      body: jsonEncode({
        'guestAccessToken': token,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      }),
    );
    final decoded = jsonDecode(response.body);

    if (response.statusCode >= 400) {
      final message = decoded is Map
          ? decoded['message'] as String? ?? 'Unable to cancel booking'
          : 'Unable to cancel booking';
      final code = decoded is Map ? decoded['error_code'] as String? : null;
      final errors = decoded is Map && decoded['errors'] is List
          ? (decoded['errors'] as List)
                .whereType<Map>()
                .map(
                  (item) => BookingApiErrorDetail.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false)
          : const <BookingApiErrorDetail>[];
      throw BookingApiException(message, code, errors);
    }

    final data = decoded is Map && decoded['data'] is Map
        ? Map<String, dynamic>.from(decoded['data'] as Map)
        : <String, dynamic>{};

    final updated = booking.copyWith(
      status: data['status'] as String? ?? 'CANCELLED',
      canCancel: data['canCancel'] == true,
      cancellationDeadline: data['cancellationDeadline'] as String?,
      cancellationBlockedReason:
          data['cancellationBlockedReason'] as String? ?? 'ALREADY_CANCELLED',
      capabilities: GuestBookingCapabilities(
        chatAvailable: booking.capabilities.chatAvailable,
        notificationsAvailable: booking.capabilities.notificationsAvailable,
        dropoffQrIssueAvailable: false,
        reviewAvailable: booking.capabilities.reviewAvailable,
        trackingAvailable: false,
        boardingQrRecoverable: false,
        boardingQrPreviouslyIssued:
            booking.capabilities.boardingQrPreviouslyIssued,
        cancelAvailable: data['canCancel'] == true,
      ),
    );
    await persist(updated);
    return updated;
  }
}

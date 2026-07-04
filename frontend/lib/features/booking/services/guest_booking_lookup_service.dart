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
    }
    await prefs.remove(_cachedBookingKey);
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
}

// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:convert';
import 'dart:html' as web;

// sessionStorage survives refresh and back navigation, but not a new session.
bool consumeFreshBookingEntry(Uri uri) {
  if (!uri.queryParameters.containsKey('service')) return false;
  final token = uri.queryParameters['entry'] ?? uri.toString();
  final key = 'trider_booking_entry_$token';
  try {
    if (web.window.sessionStorage[key] != null) return false;
    web.window.sessionStorage[key] = '1';
  } catch (_) {
    return false;
  }
  return true;
}

Map<String, dynamic>? landingRouteEntry(Uri uri) {
  try {
    final raw = web.window.sessionStorage['tride_landing_route_v1'];
    if (raw == null) return null;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    if (data['entry'] != uri.queryParameters['entry'] ||
        data['service'] != uri.queryParameters['service'] ||
        (data['expiresAt'] as num) <= DateTime.now().millisecondsSinceEpoch)
      return null;
    return data;
  } catch (_) {
    return null;
  }
}

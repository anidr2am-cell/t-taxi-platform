// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
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

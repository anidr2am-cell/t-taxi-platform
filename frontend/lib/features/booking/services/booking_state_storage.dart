import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/booking_wizard_state.dart';

class BookingStateStorage {
  static const _storageKey = 'booking_wizard_state_v1';

  Future<void> save(BookingWizardState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(state.toJson()));
  }

  Future<BookingWizardState?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) return null;
    try {
      return BookingWizardState.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}

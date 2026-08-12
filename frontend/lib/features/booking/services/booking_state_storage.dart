import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/booking_wizard_state.dart';
import '../models/booking_wizard_steps.dart';

/// TTL-backed local draft envelope for in-progress booking wizard input.
class BookingWizardDraftEnvelope {
  const BookingWizardDraftEnvelope({
    required this.version,
    required this.savedAt,
    required this.expiresAt,
    required this.state,
  });

  static const int currentVersion = 3;
  static const Duration ttl = Duration(hours: 4);

  final int version;
  final DateTime savedAt;
  final DateTime expiresAt;
  final BookingWizardState state;

  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);

  Map<String, dynamic> toJson() => {
    'version': version,
    'savedAt': savedAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'state': state.toJson(),
  };

  factory BookingWizardDraftEnvelope.fromJson(Map<String, dynamic> json) {
    return BookingWizardDraftEnvelope(
      version: json['version'] as int,
      savedAt: DateTime.parse(json['savedAt'] as String).toUtc(),
      expiresAt: DateTime.parse(json['expiresAt'] as String).toUtc(),
      state: BookingWizardState.fromJson(
        Map<String, dynamic>.from(json['state'] as Map),
      ),
    );
  }

  factory BookingWizardDraftEnvelope.create({
    required BookingWizardState state,
    required DateTime savedAt,
  }) {
    return BookingWizardDraftEnvelope(
      version: currentVersion,
      savedAt: savedAt.toUtc(),
      expiresAt: savedAt.toUtc().add(ttl),
      state: state,
    );
  }
}

class BookingStateStorage {
  BookingStateStorage({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const draftStorageKey = 'booking_wizard_draft_v2';
  static const legacyStorageKey = 'booking_wizard_state_v1';

  final DateTime Function() _now;

  /// Strips transient wizard state before persisting draft input.
  static BookingWizardState persistableState(BookingWizardState state) {
    return state.copyWith(
      step: BookingWizardSteps.clampStep(state.step),
      clearRecommendation: true,
      clearPricing: true,
      clearError: true,
    );
  }

  static BookingWizardState legacyPersistableState(BookingWizardState state) {
    return state.copyWith(
      step: BookingWizardSteps.clampStep(
        BookingWizardSteps.migrateLegacyStep(state.step),
      ),
      clearRecommendation: true,
      clearPricing: true,
      clearError: true,
    );
  }

  Future<void> save(BookingWizardState state) async {
    final prefs = await SharedPreferences.getInstance();
    final envelope = BookingWizardDraftEnvelope.create(
      state: persistableState(state),
      savedAt: _now().toUtc(),
    );
    await prefs.setString(draftStorageKey, jsonEncode(envelope.toJson()));
    await prefs.remove(legacyStorageKey);
  }

  Future<BookingWizardState?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final now = _now().toUtc();

    final fromV2 = await _loadDraftEnvelope(prefs, draftStorageKey, now);
    if (fromV2 != null) {
      return fromV2;
    }

    return _migrateLegacyV1(prefs);
  }

  Future<BookingWizardState?> _loadDraftEnvelope(
    SharedPreferences prefs,
    String key,
    DateTime now,
  ) async {
    final raw = prefs.getString(key);
    if (raw == null) {
      return null;
    }

    try {
      final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final envelope = BookingWizardDraftEnvelope.fromJson(decoded);
      if (envelope.version != 2 && envelope.version != 3) {
        await prefs.remove(key);
        return null;
      }
      if (envelope.isExpiredAt(now)) {
        await prefs.remove(key);
        return null;
      }
      if (envelope.version == 2) {
        return legacyPersistableState(envelope.state);
      }
      return persistableState(envelope.state);
    } catch (_) {
      await prefs.remove(key);
      return null;
    }
  }

  Future<BookingWizardState?> _migrateLegacyV1(SharedPreferences prefs) async {
    final raw = prefs.getString(legacyStorageKey);
    if (raw == null) {
      return null;
    }

    try {
      final state = BookingWizardState.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      await save(state);
      return legacyPersistableState(state);
    } catch (_) {
      await prefs.remove(legacyStorageKey);
      return null;
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(draftStorageKey);
    await prefs.remove(legacyStorageKey);
  }
}

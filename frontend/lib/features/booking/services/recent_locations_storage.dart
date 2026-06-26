import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/location_option.dart';

/// Persists recent locations locally. Server sync can replace [storageKey] later.
abstract class RecentLocationsRepository {
  Future<List<LocationOption>> load();
  Future<void> add(LocationOption location);
}

class GuestRecentLocationsRepository implements RecentLocationsRepository {
  static const _guestKey = 'booking_recent_locations_guest_v1';
  static const maxItems = 5;

  @override
  Future<List<LocationOption>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_guestKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => LocationOption.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> add(LocationOption location) async {
    final current = await load();
    final key = _dedupeKey(location);
    final filtered = current.where((l) => _dedupeKey(l) != key).toList();
    final updated = [location, ...filtered].take(maxItems).toList();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _guestKey,
      jsonEncode(updated.map((l) => l.toJson()).toList()),
    );
  }

  String _dedupeKey(LocationOption location) {
    if (location.placeId != null && location.placeId!.isNotEmpty) {
      return 'place:${location.placeId}';
    }
    if (location.code != null && location.code!.isNotEmpty) {
      return '${location.kind.name}:${location.code}';
    }
    return location.id;
  }
}

/// Ready for authenticated users — uses per-user key when [userId] is set.
class RecentLocationsStorage {
  RecentLocationsStorage({
    RecentLocationsRepository? guestRepository,
  }) : _guestRepository = guestRepository ?? GuestRecentLocationsRepository();

  final RecentLocationsRepository _guestRepository;
  String? _userId;

  /// Call when auth is available (not implemented in MVP).
  void setUserId(String? userId) {
    _userId = userId;
  }

  Future<RecentLocationsRepository> _activeRepository() async {
    if (_userId != null) {
      // Future: return UserRecentLocationsRepository(userId: _userId!);
    }
    return _guestRepository;
  }

  Future<List<LocationOption>> load() async {
    final repo = await _activeRepository();
    return repo.load();
  }

  Future<void> add(LocationOption location) async {
    final repo = await _activeRepository();
    await repo.add(location);
  }
}

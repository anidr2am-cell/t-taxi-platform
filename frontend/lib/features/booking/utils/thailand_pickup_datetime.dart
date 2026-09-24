/// Thailand (UTC+7) wall-clock helpers for pickup scheduling.
class ThailandPickupDateTime {
  ThailandPickupDateTime._();

  static DateTime thailandNow() {
    final adjusted = DateTime.now().toUtc().add(const Duration(hours: 7));
    return DateTime(
      adjusted.year,
      adjusted.month,
      adjusted.day,
      adjusted.hour,
      adjusted.minute,
      adjusted.second,
    );
  }

  static DateTime bangkokWallFromIso(String? iso) {
    if (iso == null || iso.isEmpty) {
      throw ArgumentError('Pickup ISO string is required');
    }
    final parsed = DateTime.parse(iso);
    final utc = parsed.toUtc();
    final bangkok = utc.add(const Duration(hours: 7));
    return DateTime(
      bangkok.year,
      bangkok.month,
      bangkok.day,
      bangkok.hour,
      bangkok.minute,
    );
  }

  static DateTime? tryBangkokWallFromIso(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    try {
      return bangkokWallFromIso(iso);
    } catch (_) {
      return null;
    }
  }

  static String serializeWallClock(DateTime wallClock) {
    String two(int n) => n.toString().padLeft(2, '0');
    String four(int n) => n.toString().padLeft(4, '0');
    return '${four(wallClock.year)}-${two(wallClock.month)}-${two(wallClock.day)}'
        'T${two(wallClock.hour)}:${two(wallClock.minute)}:00+07:00';
  }

  /// Earliest selectable calendar day for date picker (allows past pickup on edit).
  static DateTime datePickerFirstDate({
    required DateTime thailandToday,
    DateTime? currentPickup,
  }) {
    if (currentPickup == null) return thailandToday;
    final pickupDay = DateTime(
      currentPickup.year,
      currentPickup.month,
      currentPickup.day,
    );
    if (pickupDay.isBefore(thailandToday)) return pickupDay;
    return thailandToday;
  }
}

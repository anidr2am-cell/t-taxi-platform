import '../utils/pickup_time_format.dart';

/// Formats API UTC ISO timestamps for Bangkok wall-clock display.
class FlightTimeFormat {
  FlightTimeFormat._();

  static DateTime? bangkokWallClock(String? isoTimestamp) {
    if (isoTimestamp == null || isoTimestamp.isEmpty) return null;
    final utc = DateTime.tryParse(isoTimestamp)?.toUtc();
    if (utc == null) return null;
    final bangkok = utc.add(const Duration(hours: 7));
    return DateTime(
      bangkok.year,
      bangkok.month,
      bangkok.day,
      bangkok.hour,
      bangkok.minute,
    );
  }

  /// Keeps the wall-clock fields supplied by the departure airport. Provider
  /// local timestamps include an offset, but the displayed departure time must
  /// remain the airport's local time rather than the viewer device's time.
  static DateTime? localWallClock(String? isoTimestamp) {
    if (isoTimestamp == null || isoTimestamp.isEmpty) return null;
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})',
    ).firstMatch(isoTimestamp);
    if (match == null) return null;
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
    );
  }

  static String format24Hour(DateTime? value) {
    if (value == null) return '—';
    return '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }

  static String formatDate(DateTime? value) {
    if (value == null) return '—';
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  static String formatBangkokDisplay(
    String? isoUtc, {
    required String amLabel,
    required String pmLabel,
  }) {
    if (isoUtc == null || isoUtc.isEmpty) return '—';

    final bangkok = bangkokWallClock(isoUtc);
    if (bangkok == null) return '—';
    final date =
        '${bangkok.year.toString().padLeft(4, '0')}-'
        '${bangkok.month.toString().padLeft(2, '0')}-'
        '${bangkok.day.toString().padLeft(2, '0')}';
    final time = PickupTimeFormat.formatDisplay(
      hour24: bangkok.hour,
      minute: bangkok.minute,
      amLabel: amLabel,
      pmLabel: pmLabel,
    );
    return '$date $time';
  }
}

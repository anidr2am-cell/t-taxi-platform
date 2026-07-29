import '../utils/pickup_time_format.dart';

/// Formats API UTC ISO timestamps for Bangkok wall-clock display.
class FlightTimeFormat {
  FlightTimeFormat._();

  static String formatBangkokDisplay(
    String? isoUtc, {
    required String amLabel,
    required String pmLabel,
  }) {
    if (isoUtc == null || isoUtc.isEmpty) return '—';

    final utc = DateTime.parse(isoUtc).toUtc();
    final bangkok = utc.add(const Duration(hours: 7));
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

/// Same 30-minute threshold as customer [step_pickup_datetime.dart].
const int flightPickupConflictThresholdMinutes = 30;

DateTime? bangkokWallClockFromFlightIso(String? isoUtc) {
  if (isoUtc == null || isoUtc.isEmpty) return null;
  final utc = DateTime.parse(isoUtc).toUtc();
  final bangkok = utc.add(const Duration(hours: 7));
  return DateTime(
    bangkok.year,
    bangkok.month,
    bangkok.day,
    bangkok.hour,
    bangkok.minute,
  );
}

int? absoluteMinuteDifference(DateTime? left, DateTime? right) {
  if (left == null || right == null) return null;
  return left.difference(right).inMinutes.abs();
}

bool shouldShowFlightPickupConflict({
  required DateTime? manualPickupBangkok,
  required DateTime? flightArrivalBangkok,
}) {
  final diff = absoluteMinuteDifference(
    manualPickupBangkok,
    flightArrivalBangkok,
  );
  if (diff == null) return false;
  return diff >= flightPickupConflictThresholdMinutes;
}

String formatAdminPickupSummary({
  required DateTime value,
  required String dateLabel,
  required String timeLabel,
  required String amLabel,
  required String pmLabel,
}) {
  return '$dateLabel $timeLabel';
}

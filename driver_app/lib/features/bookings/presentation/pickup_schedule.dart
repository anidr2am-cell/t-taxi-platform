import '../../../l10n/app_localizations.dart';

/// Thailand (Bangkok) offset used consistently for pickup scheduling display.
const Duration bangkokOffset = Duration(hours: 7);

/// Parses booking pickup instant from API fields (prefers scheduledPickupAt ISO).
DateTime? parsePickupInstant({
  String? scheduledPickupAt,
  String? pickupDate,
  String? pickupTime,
}) {
  final scheduled = scheduledPickupAt?.trim();
  if (scheduled != null && scheduled.isNotEmpty) {
    return _toBangkokInstant(DateTime.tryParse(scheduled), scheduled);
  }
  final date = pickupDate?.trim();
  final time = pickupTime?.trim();
  if (date == null ||
      date.isEmpty ||
      time == null ||
      time.isEmpty ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
      !RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(time)) {
    return null;
  }
  final parts = date.split('-');
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
    int.parse(time.substring(0, 2)),
    int.parse(time.substring(3, 5)),
  );
}

DateTime? _toBangkokInstant(DateTime? parsed, String raw) {
  if (parsed == null) return null;
  final hasTimeZone = RegExp(r'(?:Z|[+-]\d{2}:?\d{2})$').hasMatch(raw);
  if (!hasTimeZone) {
    return DateTime(
      parsed.year,
      parsed.month,
      parsed.day,
      parsed.hour,
      parsed.minute,
      parsed.second,
      parsed.millisecond,
      parsed.microsecond,
    );
  }
  return _bangkokWallClock(parsed.toUtc().add(bangkokOffset));
}

class PickupDelayInfo {
  const PickupDelayInfo({
    required this.isPastPickup,
    required this.delay,
  });

  final bool isPastPickup;
  final Duration delay;
}

PickupDelayInfo? pickupDelayInfo({
  required String? scheduledPickupAt,
  required String? pickupDate,
  required String? pickupTime,
  DateTime Function()? now,
}) {
  final pickup = parsePickupInstant(
    scheduledPickupAt: scheduledPickupAt,
    pickupDate: pickupDate,
    pickupTime: pickupTime,
  );
  if (pickup == null) return null;
  final current = _bangkokNow(now?.call() ?? DateTime.now());
  if (!current.isAfter(pickup)) {
    return const PickupDelayInfo(isPastPickup: false, delay: Duration.zero);
  }
  return PickupDelayInfo(isPastPickup: true, delay: current.difference(pickup));
}

/// Converts any instant to Bangkok wall-clock components for stable comparisons.
DateTime _bangkokNow(DateTime instant) =>
    _bangkokWallClock(instant.toUtc().add(bangkokOffset));

DateTime _bangkokWallClock(DateTime value) => DateTime(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
      value.second,
      value.millisecond,
      value.microsecond,
    );

String? pickupDelayBannerMessage(AppLocalizations l10n, PickupDelayInfo info) {
  if (!info.isPastPickup || info.delay <= Duration.zero) return null;
  final totalMinutes = info.delay.inMinutes;
  if (totalMinutes <= 0) {
    return l10n.pickupPastDueBanner;
  }
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours > 0) {
    return l10n.pickupPastDueDelayedHoursMinutes(hours, minutes);
  }
  return l10n.pickupPastDueDelayedMinutes(minutes);
}

/// Asia/Bangkok wall-clock offset used for naive MySQL DATETIME strings.
/// Mirrors backend `serviceDateTime.util.js`.
const serviceBangkokUtcOffset = '+07:00';

/// Naive MySQL datetime with optional fractional seconds.
final RegExp _mysqlDateTimePattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})(\.\d+)?$',
);

final RegExp _explicitTimezonePattern = RegExp(
  r'(?:Z|[+-]\d{2}:\d{2})$',
  caseSensitive: false,
);

/// Parses backend service datetimes for driver urgent flows.
///
/// - Naive `YYYY-MM-DD HH:mm:ss[.fff]` values are Bangkok wall clock (+07:00).
/// - ISO-8601 strings with `Z` or an explicit offset use native parsing.
/// - Invalid or missing values return null (callers may apply a fallback).
DateTime? parseBackendServiceDateTime(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final trimmed = raw.trim();

  try {
    if (_explicitTimezonePattern.hasMatch(trimmed)) {
      return DateTime.parse(trimmed).toLocal();
    }

    final mysqlMatch = _mysqlDateTimePattern.firstMatch(trimmed);
    if (mysqlMatch != null) {
      final isoWithOffset =
          '${mysqlMatch.group(1)}-${mysqlMatch.group(2)}-${mysqlMatch.group(3)}'
          'T${mysqlMatch.group(4)}:${mysqlMatch.group(5)}:${mysqlMatch.group(6)}'
          '${mysqlMatch.group(7) ?? ''}$serviceBangkokUtcOffset';
      return DateTime.parse(isoWithOffset).toLocal();
    }

    return DateTime.parse(trimmed).toLocal();
  } on FormatException {
    return null;
  }
}

String formatCountdownMmSs(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

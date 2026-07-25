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

DateTime? _parseMysqlNaiveBangkok(String raw) {
  final mysqlMatch = _mysqlDateTimePattern.firstMatch(raw.trim());
  if (mysqlMatch == null) return null;

  final isoWithOffset =
      '${mysqlMatch.group(1)}-${mysqlMatch.group(2)}-${mysqlMatch.group(3)}'
      'T${mysqlMatch.group(4)}:${mysqlMatch.group(5)}:${mysqlMatch.group(6)}'
      '${mysqlMatch.group(7) ?? ''}$serviceBangkokUtcOffset';
  try {
    return DateTime.parse(isoWithOffset).toLocal();
  } on FormatException {
    return null;
  }
}

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

    final mysqlParsed = _parseMysqlNaiveBangkok(trimmed);
    if (mysqlParsed != null) {
      return mysqlParsed;
    }

    return DateTime.parse(trimmed).toLocal();
  } on FormatException {
    return null;
  }
}

/// Remaining time until an urgent negotiation expiry timestamp.
Duration remainingUntilBackendServiceDateTime(
  String? raw, {
  DateTime? now,
  Duration fallback = Duration.zero,
}) {
  final anchor = now ?? DateTime.now();
  if (raw == null || raw.trim().isEmpty) return fallback;

  final expiresAt = parseBackendServiceDateTime(raw);
  if (expiresAt == null) return fallback;

  final diff = expiresAt.difference(anchor);
  return diff.isNegative ? Duration.zero : diff;
}

String formatCountdownMmSs(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

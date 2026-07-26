import '../data/booking_models.dart';

String? formatBookingDateTime(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return null;

  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw;

  final hasTimeZone = RegExp(r'(?:Z|[+-]\d{2}:?\d{2})$').hasMatch(raw);
  final bangkokTime = hasTimeZone
      ? parsed.toUtc().add(const Duration(hours: 7))
      : parsed;
  return '${bangkokTime.year.toString().padLeft(4, '0')}-'
      '${bangkokTime.month.toString().padLeft(2, '0')}-'
      '${bangkokTime.day.toString().padLeft(2, '0')} '
      '${bangkokTime.hour.toString().padLeft(2, '0')}:'
      '${bangkokTime.minute.toString().padLeft(2, '0')}';
}

String formatBookingLocation(BookingLocation location) {
  final parts = <String>[
    ?location.name,
    if (location.address != null && location.address != location.name)
      location.address!,
  ];
  return parts.isEmpty ? '위치 정보 없음' : parts.join('\n');
}

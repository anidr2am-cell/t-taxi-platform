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

String? formatBookingCreatedAtLabel(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return null;

  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return null;

  final hasTimeZone = RegExp(r'(?:Z|[+-]\d{2}:?\d{2})$').hasMatch(raw);
  final bangkokTime = hasTimeZone
      ? parsed.toUtc().add(const Duration(hours: 7))
      : parsed;
  final minuteText = bangkokTime.minute.toString().padLeft(2, '0');
  return '예약: ${bangkokTime.month}월 ${bangkokTime.day}일 '
      '${bangkokTime.hour}시 $minuteText분';
}

String formatBookingLocation(BookingLocation location) {
  final lines = parseBookingLocation(location);
  if (!lines.hasPlaceName && !lines.hasAddressLine) {
    return '위치 정보 없음';
  }
  return [
    ?lines.placeName,
    if (lines.hasAddressLine) lines.addressLine,
  ].join('\n');
}

class BookingLocationLines {
  const BookingLocationLines({this.placeName, this.addressLine});

  final String? placeName;
  final String? addressLine;

  bool get hasPlaceName => placeName != null && placeName!.isNotEmpty;
  bool get hasAddressLine => addressLine != null && addressLine!.isNotEmpty;
  bool get hasSeparateAddress => hasPlaceName && hasAddressLine;
}

BookingLocationLines parseBookingLocation(BookingLocation location) {
  final primaryName = _trimmedLocationLabel(location.nameTh) ??
      _trimmedLocationLabel(location.name);
  final address = _trimmedLocationLabel(location.address);
  if (primaryName == null && address == null) {
    return const BookingLocationLines();
  }
  if (primaryName == null) {
    return BookingLocationLines(addressLine: address);
  }
  if (address == null || address == primaryName) {
    return BookingLocationLines(placeName: primaryName);
  }
  return BookingLocationLines(placeName: primaryName, addressLine: address);
}

String? _trimmedLocationLabel(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

const assignmentReleasedDefaultCloseMessage =
    '이 예약의 배정이 종료되어 목록으로 돌아갑니다.';

const assignmentReleasedAdminCloseMessage =
    '관리자에 의해 배정이 취소되어 목록으로 돌아갑니다. 자세한 사항은 고객센터로 문의해주세요.';

String assignmentReleasedCloseMessage(Map<String, dynamic> payload) {
  final reasonCode = payload['reasonCode']?.toString().trim();
  if (reasonCode == 'ADMIN_RELEASED') {
    return assignmentReleasedAdminCloseMessage;
  }
  return assignmentReleasedDefaultCloseMessage;
}

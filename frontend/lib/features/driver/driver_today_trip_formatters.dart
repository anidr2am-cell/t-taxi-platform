import 'driver_trip_contact.dart';
import 'models/driver_booking.dart';

/// Formats API pickup date/time for the driver today current-trip card.
///
/// [pickupDate] is expected as `YYYY-MM-DD` and [pickupTime] as `HH:mm`.
String formatDriverPickupRequestTime({
  required String pickupDate,
  required String pickupTime,
}) {
  const label = '고객 픽업 요청 시간 (เวลารับที่ลูกค้าขอ)';
  final dateParts = pickupDate.trim().split('-');
  final timeParts = pickupTime.trim().split(':');
  if (dateParts.length != 3 || timeParts.length < 2) {
    final fallback = '$pickupDate $pickupTime'.trim();
    return fallback.isEmpty ? label : '$label $fallback';
  }

  final month = int.tryParse(dateParts[1]);
  final day = int.tryParse(dateParts[2]);
  final hour = int.tryParse(timeParts[0]);
  final minute = int.tryParse(timeParts[1]);
  if (month == null ||
      day == null ||
      hour == null ||
      minute == null ||
      month < 1 ||
      month > 12 ||
      day < 1 ||
      day > 31 ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
    final fallback = '$pickupDate $pickupTime'.trim();
    return fallback.isEmpty ? label : '$label $fallback';
  }

  final minuteText = minute.toString().padLeft(2, '0');
  return '$label $month월 $day일 $hour시 $minuteText분';
}

/// Place label for route lines: name/nameTh pairing, then address/fallback.
String formatDriverRoutePlaceLabel(
  DriverBookingLocation? location, {
  required String fallbackAddress,
}) {
  final name = location?.name?.trim();
  final nameTh = location?.nameTh?.trim();
  final hasName = name != null && name.isNotEmpty;
  final hasNameTh = nameTh != null && nameTh.isNotEmpty;

  if (hasName && hasNameTh) {
    return name == nameTh ? name : '$name($nameTh)';
  }
  if (hasNameTh) return nameTh;
  if (hasName) return name;

  final address = location?.address?.trim();
  if (address != null && address.isNotEmpty) return address;

  if (location != null) {
    final labeled = DriverTripContact.displayLabelFor(location);
    if (labeled.isNotEmpty) return labeled;
  }

  final fallback = fallbackAddress.trim();
  return fallback.isEmpty ? '위치 정보 없음' : fallback;
}

String formatDriverRouteLineLabel({
  required String prefix,
  required DriverBookingLocation? location,
  required String fallbackAddress,
}) {
  return '$prefix - ${formatDriverRoutePlaceLabel(location, fallbackAddress: fallbackAddress)}';
}

import '../data/booking_models.dart';
import '../../../l10n/app_localizations.dart';

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

String? formatBookingCreatedAtLabel(AppLocalizations l10n, String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return null;

  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return null;

  final hasTimeZone = RegExp(r'(?:Z|[+-]\d{2}:?\d{2})$').hasMatch(raw);
  final bangkokTime = hasTimeZone
      ? parsed.toUtc().add(const Duration(hours: 7))
      : parsed;
  final minuteText = bangkokTime.minute.toString().padLeft(2, '0');
  return l10n.bookingCreatedAt(
    bangkokTime.month,
    bangkokTime.day,
    bangkokTime.hour,
    minuteText,
  );
}

String formatBookingLocation(AppLocalizations l10n, BookingLocation location) {
  final lines = parseBookingLocation(location);
  if (!lines.hasPlaceName && !lines.hasAddressLine) {
    return l10n.noLocationInfo;
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

String assignmentReleasedCloseMessage(
  AppLocalizations l10n,
  Map<String, dynamic> payload,
) {
  final reasonCode = payload['reasonCode']?.toString().trim();
  if (reasonCode == 'ADMIN_RELEASED') {
    return l10n.assignmentReleasedAdminMessage;
  }
  return l10n.assignmentReleasedDefaultMessage;
}

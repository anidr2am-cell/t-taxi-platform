/// Normalizes boarding QR payloads from camera scan, manual entry, or QR image.
String normalizeBoardingQrToken(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return trimmed;

  final uri = Uri.tryParse(trimmed);
  if (uri != null) {
    for (final key in const ['token', 'boardingQrToken', 'qrToken', 't']) {
      final value = uri.queryParameters[key]?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    final segments = uri.pathSegments.where((part) => part.trim().isNotEmpty);
    if (segments.isNotEmpty) {
      return segments.last.trim();
    }
  }

  return trimmed;
}

bool isBoardingQrTokenExpired(String? expiresAt, {DateTime? now}) {
  if (expiresAt == null || expiresAt.trim().isEmpty) return true;
  final parsed = DateTime.tryParse(expiresAt.replaceFirst(' ', 'T'));
  if (parsed == null) return true;
  return !parsed.isAfter(now ?? DateTime.now());
}

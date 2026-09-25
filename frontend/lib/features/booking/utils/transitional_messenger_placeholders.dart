/// Contact-connection M2 transitional values; not real messenger channel/id.
class TransitionalMessengerPlaceholders {
  TransitionalMessengerPlaceholders._();

  static const transitionalMessengerType = 'PENDING';
  static const transitionalMessengerIdPostCreate = 'POST_CREATE';

  static bool isTransitionalMessengerType(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed == transitionalMessengerType;
  }

  static bool isTransitionalMessengerId(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed == transitionalMessengerIdPostCreate ||
        trimmed == transitionalMessengerType;
  }

  static String sanitizeMessengerTypeField(String? value) {
    if (isTransitionalMessengerType(value)) return '';
    return value?.trim() ?? '';
  }

  static String sanitizeMessengerIdField(String? value) {
    if (isTransitionalMessengerId(value)) return '';
    return value?.trim() ?? '';
  }
}

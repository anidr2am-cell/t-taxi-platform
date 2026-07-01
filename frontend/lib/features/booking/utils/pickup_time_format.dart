/// 12-hour display and parsing for pickup time UI.
/// Internal storage remains 24-hour `HH:mm` via [BookingWizardController.formatTime].
class PickupTimeFormat {
  PickupTimeFormat._();

  static const minuteStep = 1;

  static List<int> get minuteOptions {
    final values = <int>[];
    for (var m = 0; m < 60; m += minuteStep) {
      values.add(m);
    }
    return values;
  }

  static int hour12From24(int hour24) {
    final mod = hour24 % 12;
    return mod == 0 ? 12 : mod;
  }

  static bool isPm(int hour24) => hour24 >= 12;

  static int hour24From12({required int hour12, required bool pm}) {
    final normalized = hour12 % 12;
    if (pm) {
      return normalized == 0 ? 12 : normalized + 12;
    }
    return normalized == 0 ? 0 : normalized;
  }

  static String format24h(int hour24, int minute) {
    final h = hour24.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static String formatDisplay({
    required int hour24,
    required int minute,
    required String amLabel,
    required String pmLabel,
  }) {
    final hour12 = hour12From24(hour24);
    final h = hour12.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    final period = isPm(hour24) ? pmLabel : amLabel;
    return '$h:$m $period';
  }

  static ({int hour24, int minute})? parseManualInput(
    String raw, {
    required String amLabel,
    required String pmLabel,
  }) {
    final input = raw.trim();
    if (input.isEmpty) return null;

    final normalized = input.toLowerCase();
    final amLower = amLabel.toLowerCase();
    final pmLower = pmLabel.toLowerCase();

    bool? pm;
    String timePart = input;

    if (normalized.endsWith(' pm') || normalized.endsWith('pm')) {
      pm = true;
      timePart = input.replaceAll(RegExp(r'\s*pm\s*$', caseSensitive: false), '');
    } else if (normalized.endsWith(' am') || normalized.endsWith('am')) {
      pm = false;
      timePart = input.replaceAll(RegExp(r'\s*am\s*$', caseSensitive: false), '');
    } else if (normalized.endsWith(' $pmLower') || normalized.endsWith(pmLower)) {
      pm = true;
      timePart = input.substring(0, input.length - pmLabel.length).trim();
    } else if (normalized.endsWith(' $amLower') || normalized.endsWith(amLower)) {
      pm = false;
      timePart = input.substring(0, input.length - amLabel.length).trim();
    }

    final parts = timePart.split(':');
    if (parts.length != 2) return null;

    final hourValue = int.tryParse(parts[0].trim());
    final minuteValue = int.tryParse(parts[1].trim());
    if (hourValue == null || minuteValue == null) return null;
    if (minuteValue < 0 || minuteValue > 59) return null;
    if (minuteValue % minuteStep != 0) return null;

    if (pm != null) {
      if (hourValue < 1 || hourValue > 12) return null;
      return (
        hour24: hour24From12(hour12: hourValue, pm: pm),
        minute: minuteValue,
      );
    }

    if (hourValue < 0 || hourValue > 23) return null;
    return (hour24: hourValue, minute: minuteValue);
  }
}

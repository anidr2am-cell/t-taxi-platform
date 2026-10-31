class BookingContactPreference {
  BookingContactPreference._();

  static const kakao = 'KAKAO';
  static const line = 'LINE';
  static const whatsapp = 'WHATSAPP';
  static const sms = 'SMS'; // Historical reservations only.
  static const wechat = 'WECHAT';
  static const telegram = 'TELEGRAM';
  static const values = [kakao, line, whatsapp, wechat, telegram];

  static String normalize(String? value) {
    final normalized = (value ?? '').trim().toUpperCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    return switch (normalized) {
      'KAKAO' || 'KAKAO TALK' || 'KAKAOTALK' => kakao,
      'LINE' => line,
      'WHATSAPP' => whatsapp,
      'WECHAT' || 'WE CHAT' => wechat,
      'TELEGRAM' => telegram,
      'SMS' || 'PHONE' || 'PHONE/SMS' => sms,
      _ => '',
    };
  }

  static String defaultFor({
    required String languageCode,
    String? authProvider,
  }) {
    final provider = (authProvider ?? '').toUpperCase();
    if (provider == 'KAKAO') return kakao;
    if (provider == 'LINE') return line;
    return switch (languageCode) {
      'ko' => kakao,
      'th' || 'ja' => line,
      _ => whatsapp,
    };
  }

  static String defaultDialCode(String languageCode) => switch (languageCode) {
    'ko' => '+82',
    'th' => '+66',
    'ja' => '+81',
    'zh' => '+86',
    'ru' => '+7',
    _ => '+66',
  };

  static bool usesPhone(String type) => type == whatsapp || type == sms;
  static bool requiresPhone(String type) =>
      values.contains(type) || type == sms;
  static bool allowsEmergencyPhone(String type) => false;

  static String contactPhone(String type, String dialCode, String localNumber) {
    if (!requiresPhone(type) && !allowsEmergencyPhone(type)) return '';
    final value = localNumber.trim();
    if (value.startsWith('+')) {
      final normalized = '+${value.substring(1).replaceAll(RegExp(r'\D'), '')}';
      return RegExp(r'^\+[1-9]\d{6,14}$').hasMatch(normalized)
          ? normalized
          : '';
    }
    return normalizeInternationalPhone(dialCode, value);
  }

  static String summaryValue({
    required String type,
    required String channelLabel,
    required String messengerId,
    required String dialCode,
    required String localNumber,
    String? idLabel,
  }) {
    final normalizedType = normalize(type);
    final phone = contactPhone(normalizedType, dialCode, localNumber);
    final primary = requiresPhone(normalizedType)
        ? formatInternationalPhone(phone)
        : messengerId.trim();
    final id = [kakao, line, wechat, telegram].contains(normalizedType)
        ? messengerId.trim()
        : '';
    return [
      channelLabel,
      if (primary.isNotEmpty) primary,
      if (id.isNotEmpty) '${idLabel ?? 'ID'} $id',
    ].join(' · ');
  }

  static String labelKey(String? value) => switch (normalize(value)) {
    kakao => 'booking_contact_kakao',
    line => 'booking_contact_line',
    whatsapp => 'booking_contact_whatsapp',
    wechat => 'booking_contact_wechat',
    telegram => 'booking_contact_telegram',
    _ => 'booking_contact_phone_sms',
  };

  static String formatInternationalPhone(String value) {
    final normalized = value.replaceAll(RegExp(r'[^\d+]'), '');
    if (RegExp(r'^\+82\d{10}$').hasMatch(normalized)) {
      return '${normalized.substring(0, 3)} ${normalized.substring(3, 5)}-${normalized.substring(5, 9)}-${normalized.substring(9)}';
    }
    if (RegExp(r'^\+66\d{9}$').hasMatch(normalized)) {
      return '${normalized.substring(0, 3)} ${normalized.substring(3, 5)}-${normalized.substring(5, 8)}-${normalized.substring(8)}';
    }
    if (RegExp(r'^\+81\d{10}$').hasMatch(normalized)) {
      return '${normalized.substring(0, 3)} ${normalized.substring(3, 5)}-${normalized.substring(5, 9)}-${normalized.substring(9)}';
    }
    if (RegExp(r'^\+86\d{11}$').hasMatch(normalized)) {
      return '${normalized.substring(0, 3)} ${normalized.substring(3, 6)}-${normalized.substring(6, 10)}-${normalized.substring(10)}';
    }
    return normalized;
  }

  static String normalizeInternationalPhone(
    String dialCode,
    String localNumber,
  ) {
    final countryDialCodes = {
      'TH': '+66',
      'KR': '+82',
      'JP': '+81',
      'CN': '+86',
    };
    final resolvedDial =
        countryDialCodes[dialCode.trim().toUpperCase()] ?? dialCode;
    var dial = resolvedDial.replaceAll(RegExp(r'\D'), '');
    var local = localNumber.replaceAll(RegExp(r'\D'), '');
    if (dial == '7' && local.length == 11 && local.startsWith('8')) {
      local = local.substring(1);
    }
    if (local.startsWith('0')) local = local.substring(1);
    if (dial.isEmpty || local.isEmpty) return '';
    final normalized = '+$dial$local';
    return RegExp(r'^\+[1-9]\d{6,14}$').hasMatch(normalized) ? normalized : '';
  }
}

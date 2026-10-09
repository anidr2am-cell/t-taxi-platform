class BookingContactPreference {
  BookingContactPreference._();

  static const kakao = 'KAKAO';
  static const line = 'LINE';
  static const whatsapp = 'WHATSAPP';
  static const sms = 'SMS';
  static const values = [kakao, line, whatsapp, sms];

  static String normalize(String? value) {
    final normalized = (value ?? '').trim().toUpperCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    return switch (normalized) {
      'KAKAO' || 'KAKAO TALK' || 'KAKAOTALK' => kakao,
      'LINE' => line,
      'WHATSAPP' => whatsapp,
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
    _ => '+66',
  };

  static bool usesPhone(String type) => type == whatsapp || type == sms;
  static bool allowsEmergencyPhone(String type) =>
      type == kakao || type == line;

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
    final resolvedDial = countryDialCodes[dialCode.trim().toUpperCase()] ?? dialCode;
    var dial = resolvedDial.replaceAll(RegExp(r'\D'), '');
    var local = localNumber.replaceAll(RegExp(r'\D'), '');
    if (local.startsWith('0')) local = local.substring(1);
    if (dial.isEmpty || local.isEmpty) return '';
    final normalized = '+$dial$local';
    return RegExp(r'^\+[1-9]\d{6,14}$').hasMatch(normalized) ? normalized : '';
  }
}

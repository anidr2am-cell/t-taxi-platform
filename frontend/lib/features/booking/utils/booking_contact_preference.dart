import 'package:phone_numbers_parser/phone_numbers_parser.dart';
import 'package:phone_numbers_parser/metadata.dart';
import '../../../models/calling_countries.dart';

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
      'th' || 'ja' || 'zh-TW' => line,
      _ => whatsapp,
    };
  }

  static String defaultDialCode(String languageCode) => switch (languageCode) {
    'ko' => '+82',
    'th' => '+66',
    'ja' => '+81',
    'zh' => '+86',
    'zh-TW' => '+886',
    'ru' => '+7',
    _ => '+66',
  };

  static bool usesPhone(String type) => type == whatsapp || type == sms;
  static bool requiresPhone(String type) =>
      values.contains(type) || type == sms;
  static bool allowsEmergencyPhone(String type) => false;

  static String contactPhone(String type, String dialCode, String localNumber) {
    if (!requiresPhone(type) && !allowsEmergencyPhone(type)) return '';
    return normalizeBookingPhone(dialCode, localNumber);
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

  static String normalizeBookingPhone(String dialCode, String localNumber) {
    final raw = localNumber.trim();
    if (raw.isEmpty || !RegExp(r'^[+0-9\s().-]+$').hasMatch(raw)) return '';
    // Full international numbers are self-describing, including old drafts
    // without a dial selection and numbers pasted under a different default.
    if (raw.startsWith('+') || raw.startsWith('00')) {
      try {
        final phone = PhoneNumber.parse(
          raw.startsWith('00') ? '+${raw.substring(2)}' : raw,
        );
        return phone.isValidLength() &&
                RegExp(r'^\+[1-9]\d{6,14}$').hasMatch(phone.international)
            ? phone.international
            : '';
      } catch (_) {
        return '';
      }
    }
    final selected = dialCode.trim().toUpperCase();
    final country = callingCountries
        .where(
          (c) =>
              c.code == selected ||
              c.dialCode == '+${dialCode.replaceAll(RegExp(r'\D'), '')}',
        )
        .firstOrNull;
    final dial = (country?.dialCode ?? dialCode).replaceAll(RegExp(r'\D'), '');
    IsoCode? iso;
    // Shared calling codes retain the chosen dial prefix; metadata resolves the national number.
    final preferredIso = switch (dial) {
      '1' => 'US',
      '7' => 'RU',
      '44' => 'GB',
      _ => country?.code,
    };
    for (final code in IsoCode.values) {
      if (code.name == preferredIso) iso = code;
    }
    if (iso == null || dial.isEmpty) return '';
    String? parse(String input) {
      try {
        final phone = input.trim().startsWith('+')
            ? PhoneNumber.parse(input)
            : PhoneNumber.parse(input, destinationCountry: iso);
        if (phone.countryCode != dial || !phone.isValidLength()) return null;
        return RegExp(r'^\+[1-9]\d{6,14}$').hasMatch(phone.international)
            ? phone.international
            : null;
      } catch (_) {
        return null;
      }
    }

    final normalized = parse(
      raw.startsWith('00') ? '+${raw.substring(2)}' : raw,
    );
    if (normalized != null) return normalized;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    final prefix = metadataByIsoCode[iso]?.nationalPrefix;
    if (!raw.startsWith('+') &&
        prefix != null &&
        RegExp(r'^\d+$').hasMatch(prefix) &&
        digits.startsWith(prefix)) {
      final candidate = parse('+$dial${digits.substring(prefix.length)}');
      if (candidate != null) return candidate;
    }
    if (!raw.startsWith('+') && digits.startsWith(dial)) {
      return parse(digits.substring(dial.length)) ?? '';
    }
    return '';
  }

  static String phoneExample(String dial) => switch (dial) {
    '+82' => '010-1234-5678',
    '+66' => '081-234-5678',
    '+81' => '090-1234-5678',
    '+86' => '138 0013 8000',
    '+886' => '0912 345 678',
    '+1' => '202-555-0123',
    '+44' => '07700 900123',
    '+39' => '06 1234 5678',
    '+7' => '8 916 123 45 67',
    _ => _internationalExample(dial),
  };
  static String _internationalExample(String dial) {
    final country = callingCountries
        .where((c) => c.dialCode == dial)
        .firstOrNull;
    for (final iso in IsoCode.values) {
      if (iso.name != country?.code) continue;
      final example = metadataExamplesByIsoCode[iso];
      final digits = (example?.mobile.isNotEmpty == true)
          ? example!.mobile
          : example?.fixedLine;
      if (digits != null && digits.isNotEmpty) return '$dial $digits';
    }
    return dial;
  }
}

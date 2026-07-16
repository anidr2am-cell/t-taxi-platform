import '../../../l10n/app_localizations.dart';

class CustomerBookingFormat {
  CustomerBookingFormat._();

  static String money(num amount, String currency) {
    final normalizedCurrency = currency.trim().toUpperCase();
    final rounded = amount.round();
    final formatted = _withThousands(rounded);
    if (normalizedCurrency == 'THB') return '฿$formatted';
    return '$formatted ${normalizedCurrency.isEmpty ? 'THB' : normalizedCurrency}';
  }

  static String paymentMethod(AppLocalizations l10n, String? code) {
    switch ((code ?? '').trim().toUpperCase()) {
      case 'PAY_DRIVER':
        return l10n.t('customer_payment_pay_driver');
      case 'CASH':
        return l10n.t('customer_payment_cash');
      case 'QR':
      case 'QR_PAYMENT':
        return l10n.t('customer_payment_qr');
      case 'CARD':
      case 'CREDIT_CARD':
        return l10n.t('customer_payment_card');
      case 'BANK_TRANSFER':
        return l10n.t('customer_payment_bank_transfer');
      default:
        return l10n.t('customer_payment_unknown');
    }
  }

  static String pickupDateTime(AppLocalizations l10n, String? value) {
    final parsed = _parseThailandDateTime(value);
    if (parsed == null) return '-';
    return _formatDateTime(l10n.languageCode, parsed);
  }

  static String pickupDate(AppLocalizations l10n, String? date, String? time) {
    final value = date == null || date.isEmpty
        ? null
        : '${date}T${(time == null || time.isEmpty) ? '00:00' : time}:00+07:00';
    return pickupDateTime(l10n, value);
  }

  static String _withThousands(int value) {
    final negative = value < 0;
    final digits = value.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      final remaining = digits.length - i;
      buffer.write(digits[i]);
      if (remaining > 1 && remaining % 3 == 1) buffer.write(',');
    }
    return negative ? '-$buffer' : buffer.toString();
  }

  static DateTime? _parseThailandDateTime(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final normalized = value.trim().replaceFirst(' ', 'T');
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?(?:\+07:00|Z)?$',
    ).firstMatch(normalized);
    if (match == null) return null;
    final parts = List.generate(
      6,
      (index) => int.tryParse(match.group(index + 1) ?? '0'),
    );
    if (parts.any((part) => part == null)) return null;
    return DateTime(
      parts[0]!,
      parts[1]!,
      parts[2]!,
      parts[3]!,
      parts[4]!,
      parts[5]!,
    );
  }

  static String _formatDateTime(String languageCode, DateTime value) {
    final lang = languageCode.toLowerCase();
    if (lang == 'ko') {
      final period = value.hour < 12 ? '오전' : '오후';
      final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
      return '${value.year}년 ${value.month}월 ${value.day}일 $period $hour:${_two(value.minute)}';
    }
    if (lang == 'th') {
      const months = [
        'ม.ค.',
        'ก.พ.',
        'มี.ค.',
        'เม.ย.',
        'พ.ค.',
        'มิ.ย.',
        'ก.ค.',
        'ส.ค.',
        'ก.ย.',
        'ต.ค.',
        'พ.ย.',
        'ธ.ค.',
      ];
      return '${value.day} ${months[value.month - 1]} ${value.year} ${_two(value.hour)}:${_two(value.minute)}';
    }
    if (lang == 'ja') {
      return '${value.year}年${value.month}月${value.day}日 ${_two(value.hour)}:${_two(value.minute)}';
    }
    if (lang.startsWith('zh')) {
      return '${value.year}年${value.month}月${value.day}日 ${_two(value.hour)}:${_two(value.minute)}';
    }

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final period = value.hour < 12 ? 'AM' : 'PM';
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    return '${months[value.month - 1]} ${value.day}, ${value.year}, $hour:${_two(value.minute)} $period';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

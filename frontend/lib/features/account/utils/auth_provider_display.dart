import '../../../l10n/app_localizations.dart';

abstract final class AuthProviderDisplay {
  static const google = 'GOOGLE';
  static const kakao = 'KAKAO';
  static const line = 'LINE';

  static String? labelForProvider(AppLocalizations l10n, String? provider) {
    switch (provider?.toUpperCase()) {
      case google:
        return l10n.t('account_login_provider_google');
      case kakao:
        return l10n.t('account_login_provider_kakao');
      case line:
        return l10n.t('account_login_provider_line');
      default:
        return null;
    }
  }

  static String formatPoints(int value) {
    final digits = value.abs().toString();
    final buffer = StringBuffer(value < 0 ? '-' : '');
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[index]);
    }
    return buffer.toString();
  }
}

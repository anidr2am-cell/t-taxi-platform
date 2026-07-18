class DriverMoneyFormat {
  DriverMoneyFormat._();

  static String money(num amount, String? currency) {
    final normalizedCurrency = (currency ?? '').trim().toUpperCase();
    final formatted = _formatNumber(amount);
    if (normalizedCurrency.isEmpty || normalizedCurrency == 'THB') {
      return 'THB $formatted';
    }
    return '$formatted $normalizedCurrency';
  }

  static String? maybeMoney(num? amount, String? currency) {
    if (amount == null) return null;
    return money(amount, currency);
  }

  static String _formatNumber(num value) {
    final asDouble = value.toDouble();
    final decimals = asDouble == asDouble.roundToDouble() ? 0 : 2;
    final text = asDouble.abs().toStringAsFixed(decimals);
    final parts = text.split('.');
    final whole = parts.first;
    final buffer = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      final remaining = whole.length - i;
      buffer.write(whole[i]);
      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write(',');
      }
    }
    final sign = asDouble < 0 ? '-' : '';
    final fractional = parts.length > 1 ? '.${parts[1]}' : '';
    return '$sign$buffer$fractional';
  }
}

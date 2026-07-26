class AirportLabelResolver {
  const AirportLabelResolver._();

  static final RegExp _ambiguousCityOnly = RegExp(
    r'^(bangkok|chiang\s*mai|phuket|pattaya|rayong|hua\s*hin|thailand|th)'
    r'(,\s*(thailand|th))?$',
    caseSensitive: false,
  );

  static final RegExp _iataOnly = RegExp(
    r'^(bkk|dmk|cnx|hkt)(\s*,\s*(thailand|th))?$',
    caseSensitive: false,
  );

  static const _airports = <_AirportLabel>[
    _AirportLabel('BKK', 'BKK — Suvarnabhumi Airport'),
    _AirportLabel('DMK', 'DMK — Don Mueang International Airport'),
    _AirportLabel('CNX', 'CNX — Chiang Mai International Airport'),
    _AirportLabel('HKT', 'HKT — Phuket International Airport'),
    _AirportLabel('UTP', 'UTP — U-Tapao Rayong-Pattaya International Airport'),
  ];

  static String displayLabelFor(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    return _resolveKnownAirport(trimmed)?.displayName ?? trimmed;
  }

  static _AirportLabel? _resolveKnownAirport(String value) {
    final haystack = value.trim().toUpperCase();
    if (haystack.isEmpty) return null;
    final compact = haystack.replaceAll(RegExp(r'[^A-Z0-9]'), '');

    for (final airport in _airports) {
      final code = airport.code;
      final official = airport.displayName
          .replaceFirst(RegExp('^$code\\s*[—-]\\s*', caseSensitive: false), '')
          .trim()
          .toUpperCase();

      if (official.length >= 8 && haystack.contains(official)) {
        return airport;
      }

      final normalizedSingle = haystack.replaceAll(RegExp(r'\s+'), ' ');
      if (_iataOnly.hasMatch(normalizedSingle) &&
          normalizedSingle.startsWith(code)) {
        return airport;
      }

      final codeToken = RegExp(
        '(^|[^A-Z0-9])$code([^A-Z0-9]|\$)',
        caseSensitive: false,
      );
      if (codeToken.hasMatch(haystack)) {
        final hasAirportWord = haystack.contains('AIRPORT');
        final hasOfficial = official.length >= 8 && haystack.contains(official);
        final labeled = RegExp(
          '$code\\s*[—-]\\s*',
          caseSensitive: false,
        ).hasMatch(haystack);
        if (hasAirportWord || hasOfficial || labeled) {
          return airport;
        }
      }

      if (compact.contains(
            '$code${official.replaceAll(RegExp(r'[^A-Z0-9]'), '')}',
          ) &&
          official.length >= 8) {
        return airport;
      }
    }
    return null;
  }

  static bool isAmbiguousCityOrIataOnly(String value) {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    return normalized.isEmpty ||
        _ambiguousCityOnly.hasMatch(normalized) ||
        _iataOnly.hasMatch(normalized);
  }
}

class _AirportLabel {
  const _AirportLabel(this.code, this.displayName);

  final String code;
  final String displayName;
}

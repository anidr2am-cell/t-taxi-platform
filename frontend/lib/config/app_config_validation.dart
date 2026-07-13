class AppConfigValidation {
  static const String development = 'development';
  static const String staging = 'staging';
  static const String production = 'production';

  static String normalizeEnvironment(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return development;
    return normalized;
  }

  static bool isProductionEnvironment(String value) =>
      normalizeEnvironment(value) == production;

  static String resolveApiBaseUrl({
    required String appEnvironment,
    required String apiBaseUrl,
    String developmentDefault = 'http://localhost:3000',
  }) {
    final normalizedEnvironment = normalizeEnvironment(appEnvironment);
    final normalizedUrl = _normalizeLocalHost(apiBaseUrl.trim());

    if (!isProductionEnvironment(normalizedEnvironment)) {
      return normalizedUrl.isEmpty ? developmentDefault : normalizedUrl;
    }

    _validateProductionUrl(
      name: 'API_BASE_URL',
      value: normalizedUrl,
      allowSameOriginApiPath: true,
    );
    return normalizedUrl;
  }

  static String resolveSocketUrl({
    required String appEnvironment,
    required String socketUrl,
    required String apiBaseUrl,
  }) {
    final normalizedSocketUrl = _normalizeLocalHost(socketUrl.trim());
    final fallbackUrl = apiBaseUrl.trim();
    final resolved = normalizedSocketUrl.isEmpty
        ? fallbackUrl
        : normalizedSocketUrl;

    if (isProductionEnvironment(appEnvironment)) {
      _validateProductionUrl(
        name: 'SOCKET_URL',
        value: resolved,
        allowSameOriginApiPath: false,
      );
    }

    return resolved;
  }

  static String _normalizeLocalHost(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host != 'location') return value;
    return uri.replace(host: 'localhost').toString();
  }

  static void _validateProductionUrl({
    required String name,
    required String value,
    required bool allowSameOriginApiPath,
  }) {
    if (value.trim().isEmpty) {
      throw StateError('$name is required when APP_ENV=production');
    }

    if (allowSameOriginApiPath && value == '/api') {
      return;
    }

    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw StateError(
        '$name must be /api or an absolute https URL when APP_ENV=production',
      );
    }

    final host = uri.host.toLowerCase();
    if (host == 'localhost' || host == '127.0.0.1') {
      throw StateError(
        '$name must not point to localhost when APP_ENV=production',
      );
    }

    if (uri.scheme != 'https') {
      throw StateError('$name must use https when APP_ENV=production');
    }
  }
}

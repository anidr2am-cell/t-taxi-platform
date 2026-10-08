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

  static bool isDevelopmentEnvironment(String value) =>
      normalizeEnvironment(value) == development;

  static String resolveApiBaseUrl({
    required String appEnvironment,
    required String apiBaseUrl,
    String developmentDefault = 'http://localhost:3000',
  }) {
    final normalizedEnvironment = normalizeEnvironment(appEnvironment);
    final normalizedUrl = _normalizeLocalHost(apiBaseUrl.trim());

    if (isDevelopmentEnvironment(normalizedEnvironment)) {
      return normalizedUrl.isEmpty ? developmentDefault : normalizedUrl;
    }

    _validateDeployedUrl(
      name: 'API_BASE_URL',
      value: normalizedUrl,
      allowSameOriginApiPath: true,
      requireHttps: isProductionEnvironment(normalizedEnvironment),
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

    if (!isDevelopmentEnvironment(appEnvironment)) {
      _validateDeployedUrl(
        name: 'SOCKET_URL',
        value: resolved,
        allowSameOriginApiPath: false,
        requireHttps: isProductionEnvironment(appEnvironment),
      );
    }

    return resolved;
  }

  static String _normalizeLocalHost(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host != 'location') return value;
    return uri.replace(host: 'localhost').toString();
  }

  static void _validateDeployedUrl({
    required String name,
    required String value,
    required bool allowSameOriginApiPath,
    required bool requireHttps,
  }) {
    if (value.trim().isEmpty) {
      throw StateError('$name is required outside local development');
    }

    if (allowSameOriginApiPath && value == '/api') {
      return;
    }

    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw StateError(
        '$name must be /api or an absolute URL outside local development',
      );
    }

    final host = uri.host.toLowerCase();
    if (host == 'localhost' || host == '127.0.0.1') {
      throw StateError(
        '$name must not point to localhost outside local development',
      );
    }

    if (requireHttps && uri.scheme != 'https') {
      throw StateError('$name must use https when APP_ENV=production');
    }

    if (uri.scheme != 'https' && uri.scheme != 'http') {
      throw StateError('$name must use http or https');
    }
  }
}

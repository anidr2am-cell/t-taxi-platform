import 'app_environment.dart';

class AppConfig {
  const AppConfig({
    required this.environment,
    required this.appName,
    required this.apiBaseUrl,
  });

  factory AppConfig.forEnvironment(AppEnvironment environment) {
    return switch (environment) {
      AppEnvironment.dev => const AppConfig(
        environment: AppEnvironment.dev,
        appName: 'TRide Driver DEV',
        apiBaseUrl: 'http://10.0.2.2:3000',
      ),
      AppEnvironment.stg => const AppConfig(
        environment: AppEnvironment.stg,
        appName: 'TRide Driver STG',
        apiBaseUrl: 'https://trider.taxi',
      ),
      AppEnvironment.prod => const AppConfig(
        environment: AppEnvironment.prod,
        appName: 'TRide Driver',
        apiBaseUrl: '',
      ),
    };
  }

  final AppEnvironment environment;
  final String appName;
  final String apiBaseUrl;

  Uri endpoint(String path) {
    final baseUri = _validatedBaseUri();
    final basePath = baseUri.path.replaceFirst(RegExp(r'/$'), '');
    var requestPath = path.startsWith('/') ? path : '/$path';
    if (basePath.endsWith('/api/v1') && requestPath.startsWith('/api/v1/')) {
      requestPath = requestPath.substring('/api/v1'.length);
    }
    return baseUri.replace(path: '$basePath$requestPath');
  }

  Uri _validatedBaseUri() {
    final value = apiBaseUrl.trim();
    if (value.isEmpty) {
      throw StateError('${environment.label} API 주소가 설정되지 않았습니다.');
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw StateError('${environment.label} API 주소가 올바르지 않습니다.');
    }
    if (environment != AppEnvironment.dev && uri.scheme != 'https') {
      throw StateError('${environment.label} API는 HTTPS만 허용합니다.');
    }
    if (environment == AppEnvironment.dev &&
        uri.scheme != 'http' &&
        uri.scheme != 'https') {
      throw StateError('DEV API는 HTTP 또는 HTTPS 주소여야 합니다.');
    }
    return uri.replace(path: uri.path.replaceFirst(RegExp(r'/$'), ''));
  }
}

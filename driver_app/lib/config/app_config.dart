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
        apiBaseUrl: 'http://103.60.127.213:3100',
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
    if (apiBaseUrl.isEmpty) {
      throw StateError('API endpoint is not configured for this environment.');
    }
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse(
      '${apiBaseUrl.replaceAll(RegExp(r'/$'), '')}$normalizedPath',
    );
  }
}

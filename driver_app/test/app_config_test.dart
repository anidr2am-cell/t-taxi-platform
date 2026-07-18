import 'package:flutter_test/flutter_test.dart';
import 'package:tride_driver/config/app_config.dart';
import 'package:tride_driver/config/app_environment.dart';

AppConfig customConfig(AppEnvironment environment, String apiBaseUrl) {
  return AppConfig(
    environment: environment,
    appName: 'Test',
    apiBaseUrl: apiBaseUrl,
  );
}

void main() {
  test('DEV allows an HTTP API URL', () {
    final config = AppConfig.forEnvironment(AppEnvironment.dev);
    expect(config.environment, AppEnvironment.dev);
    expect(config.appName, 'TRide Driver DEV');
    expect(
      config.endpoint('/api/v1/auth/login').toString(),
      'http://10.0.2.2:3000/api/v1/auth/login',
    );
  });

  test('STG uses the repository-confirmed HTTPS staging API', () {
    final config = AppConfig.forEnvironment(AppEnvironment.stg);
    expect(config.environment, AppEnvironment.stg);
    expect(config.appName, 'TRide Driver STG');
    expect(
      config.endpoint('/api/v1/auth/login').toString(),
      'https://trider.taxi/api/v1/auth/login',
    );
  });

  test('STG allows HTTPS', () {
    final config = customConfig(AppEnvironment.stg, 'https://staging.test');
    expect(
      config.endpoint('/api/v1/auth/me').toString(),
      'https://staging.test/api/v1/auth/me',
    );
  });

  test('STG blocks HTTP', () {
    final config = customConfig(AppEnvironment.stg, 'http://staging.test');
    expect(() => config.endpoint('/api/v1/auth/me'), throwsStateError);
  });

  test('PROD blocks HTTP', () {
    final config = customConfig(AppEnvironment.prod, 'http://api.test');
    expect(() => config.endpoint('/api/v1/auth/me'), throwsStateError);
  });

  test('empty STG and PROD URLs fail safely', () {
    for (final environment in [AppEnvironment.stg, AppEnvironment.prod]) {
      final config = customConfig(environment, '');
      expect(() => config.endpoint('/api/v1/auth/me'), throwsStateError);
    }
  });

  test('endpoint combines paths with one separator', () {
    final config = customConfig(AppEnvironment.stg, 'https://staging.test/');
    expect(
      config.endpoint('api/v1/auth/login').toString(),
      'https://staging.test/api/v1/auth/login',
    );
  });

  test('endpoint does not duplicate an existing API prefix', () {
    final config = customConfig(
      AppEnvironment.stg,
      'https://staging.test/api/v1',
    );
    expect(
      config.endpoint('/api/v1/auth/login').toString(),
      'https://staging.test/api/v1/auth/login',
    );
  });

  test('PROD remains identified with its API intentionally disabled', () {
    final config = AppConfig.forEnvironment(AppEnvironment.prod);
    expect(config.environment, AppEnvironment.prod);
    expect(config.appName, 'TRide Driver');
    expect(config.apiBaseUrl, isEmpty);
    expect(() => config.endpoint('/api/v1/auth/login'), throwsStateError);
  });
}

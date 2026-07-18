import 'package:flutter_test/flutter_test.dart';
import 'package:tride_driver/config/app_config.dart';
import 'package:tride_driver/config/app_environment.dart';

void main() {
  test('DEV environment has the expected identity', () {
    final config = AppConfig.forEnvironment(AppEnvironment.dev);
    expect(config.environment, AppEnvironment.dev);
    expect(config.appName, 'TRide Driver DEV');
    expect(config.apiBaseUrl, 'http://10.0.2.2:3000');
  });

  test('STG environment uses the documented staging API', () {
    final config = AppConfig.forEnvironment(AppEnvironment.stg);
    expect(config.environment, AppEnvironment.stg);
    expect(config.appName, 'TRide Driver STG');
    expect(
      config.endpoint('/api/v1/auth/login').toString(),
      'http://103.60.127.213:3100/api/v1/auth/login',
    );
  });

  test('PROD environment is identified but API remains disabled', () {
    final config = AppConfig.forEnvironment(AppEnvironment.prod);
    expect(config.environment, AppEnvironment.prod);
    expect(config.appName, 'TRide Driver');
    expect(config.apiBaseUrl, isEmpty);
    expect(() => config.endpoint('/api/v1/auth/login'), throwsStateError);
  });
}

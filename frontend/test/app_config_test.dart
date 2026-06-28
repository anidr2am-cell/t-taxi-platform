import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/config/app_config.dart';

void main() {
  test('apiBaseUrl defaults to localhost backend', () {
    expect(AppConfig.apiBaseUrl, 'http://localhost:3000');
  });
}

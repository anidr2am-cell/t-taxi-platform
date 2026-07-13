import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/config/app_config.dart';
import 'package:frontend/config/app_config_validation.dart';

void main() {
  test('apiBaseUrl defaults to localhost backend', () {
    expect(AppConfig.apiBaseUrl, 'http://localhost:3000');
  });

  group('production config validation', () {
    test('development allows default localhost fallback', () {
      expect(
        AppConfigValidation.resolveApiBaseUrl(
          appEnvironment: 'development',
          apiBaseUrl: '',
        ),
        'http://localhost:3000',
      );
    });

    test('staging allows explicit localhost URL for isolated smoke builds', () {
      expect(
        AppConfigValidation.resolveApiBaseUrl(
          appEnvironment: 'staging',
          apiBaseUrl: 'http://localhost:3100',
        ),
        'http://localhost:3100',
      );
    });

    test('production rejects missing API_BASE_URL', () {
      expect(
        () => AppConfigValidation.resolveApiBaseUrl(
          appEnvironment: 'production',
          apiBaseUrl: '',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('production rejects localhost API_BASE_URL', () {
      expect(
        () => AppConfigValidation.resolveApiBaseUrl(
          appEnvironment: 'production',
          apiBaseUrl: 'http://localhost:3100',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('production rejects 127.0.0.1 API_BASE_URL', () {
      expect(
        () => AppConfigValidation.resolveApiBaseUrl(
          appEnvironment: 'production',
          apiBaseUrl: 'http://127.0.0.1:3100',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('production rejects non-https absolute API_BASE_URL', () {
      expect(
        () => AppConfigValidation.resolveApiBaseUrl(
          appEnvironment: 'production',
          apiBaseUrl: 'http://api.example.com',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('production allows same-origin /api API_BASE_URL', () {
      expect(
        AppConfigValidation.resolveApiBaseUrl(
          appEnvironment: 'production',
          apiBaseUrl: '/api',
        ),
        '/api',
      );
    });

    test('production allows https API_BASE_URL', () {
      expect(
        AppConfigValidation.resolveApiBaseUrl(
          appEnvironment: 'production',
          apiBaseUrl: 'https://api.example.com',
        ),
        'https://api.example.com',
      );
    });

    test(
      'production rejects missing SOCKET_URL when API_BASE_URL is invalid',
      () {
        expect(
          () => AppConfigValidation.resolveSocketUrl(
            appEnvironment: 'production',
            socketUrl: '',
            apiBaseUrl: '',
          ),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('production allows https SOCKET_URL', () {
      expect(
        AppConfigValidation.resolveSocketUrl(
          appEnvironment: 'production',
          socketUrl: 'https://api.example.com',
          apiBaseUrl: '/api',
        ),
        'https://api.example.com',
      );
    });

    test('production rejects localhost SOCKET_URL', () {
      expect(
        () => AppConfigValidation.resolveSocketUrl(
          appEnvironment: 'production',
          socketUrl: 'http://localhost:3100',
          apiBaseUrl: '/api',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}

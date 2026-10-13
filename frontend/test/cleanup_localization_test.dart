import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_exception.dart';
import 'package:frontend/features/driver/services/driver_api_service.dart';
import 'package:frontend/features/driver/utils/driver_login_error.dart';
import 'package:frontend/l10n/app_localizations.dart';

void main() {
  test('driver login errors never expose raw API exception text', () {
    final l10n = AppLocalizations('ko');
    final cases = <Object, String>{
      const ApiException(ApiFailureKind.unauthorized, statusCode: 401, message: 'ApiException(secret)'): 'driver_login_error_credentials',
      const DriverApiException('raw failure', statusCode: 401): 'driver_login_error_credentials',
      TimeoutException('raw timeout'): 'driver_login_error_network',
      const ApiException(ApiFailureKind.unavailable): 'driver_login_error_network',
      const ApiException(ApiFailureKind.server, statusCode: 503): 'driver_login_error_server',
      const ApiException(ApiFailureKind.invalidResponse, message: '<html>'): 'driver_login_error_server',
      StateError('internal details'): 'driver_login_error_unknown',
    };
    for (final entry in cases.entries) {
      final message = driverLoginError(l10n, entry.key);
      expect(message, l10n.t(entry.value));
      expect(message, contains('\n'));
      expect(message, isNot(contains('ApiException')));
      expect(message, isNot(contains('internal details')));
      expect(message, isNot(contains('<html>')));
    }
  });
  test('admin dispatch and flight labels have five real translations', () {
    for (final language in AppLocalizations.supportedLanguages) {
      final l10n = AppLocalizations(language);
      for (final key in ['admin_dispatch_assign_driver', 'admin_dispatch_reassign_driver',
        'admin_dispatch_assigned_driver', 'admin_dispatch_unassigned',
        'admin_dispatch_next_action_none', 'admin_dispatch_next_action_assign',
        'admin_ui_payment_status', 'admin_ui_scheduled_arrival',
        'admin_ui_estimated_arrival', 'admin_ui_delay_status', 'admin_ui_delay_minutes',
        'admin_ui_vehicle']) {
        expect(l10n.t(key), isNot(key), reason: '$language $key');
        if (language != 'en') expect(l10n.t(key), isNot(AppLocalizations('en').t(key)), reason: '$language $key');
      }
    }
  });
}

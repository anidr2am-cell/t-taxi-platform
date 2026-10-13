import 'dart:async';
import 'package:http/http.dart' as http;
import '../../../core/network/api_exception.dart';
import '../../../l10n/app_localizations.dart';
import '../services/driver_api_service.dart';

String driverLoginError(AppLocalizations l10n, Object error) {
  String key = 'driver_login_error_unknown';
  final status = error is ApiException
      ? error.statusCode
      : error is DriverApiException ? error.statusCode : null;
  if (error is TimeoutException || error is http.ClientException ||
      (error is ApiException && (error.kind == ApiFailureKind.timeout ||
          error.kind == ApiFailureKind.unavailable))) {
    key = 'driver_login_error_network';
  } else if (status == 401 || status == 400 ||
      (error is ApiException && error.kind == ApiFailureKind.unauthorized)) {
    key = 'driver_login_error_credentials';
  } else if ((status != null && status >= 500) ||
      (error is ApiException && (error.kind == ApiFailureKind.server ||
          error.kind == ApiFailureKind.invalidResponse))) {
    key = 'driver_login_error_server';
  }
  return l10n.t(key);
}

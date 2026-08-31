import 'package:http/http.dart' as http;

import '../../../config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/auth_token_refresher.dart';
import 'auth_token_storage.dart';

/// Shared customer auth HTTP stack: token storage + refresh + authenticated client.
class CustomerSession {
  CustomerSession._(
    this.tokenStorage, {
    ApiClient? apiClient,
    AuthTokenRefresher? tokenRefresher,
    http.Client? httpClient,
    String? baseUrl,
  }) {
    final resolvedBaseUrl = baseUrl ?? AppConfig.apiBaseUrl;
    if (apiClient != null) {
      this.apiClient = apiClient;
      refresher =
          tokenRefresher ??
          AuthTokenRefresher(
            storage: tokenStorage,
            client: ApiClient(baseUrl: resolvedBaseUrl, httpClient: httpClient),
          );
      return;
    }

    final refreshClient = ApiClient(
      baseUrl: resolvedBaseUrl,
      httpClient: httpClient,
    );
    refresher = tokenRefresher ??
        AuthTokenRefresher(
          storage: tokenStorage,
          client: refreshClient,
        );
    this.apiClient = ApiClient(
      baseUrl: resolvedBaseUrl,
      httpClient: httpClient,
      tokenRefresher: refresher,
    );
  }

  factory CustomerSession({
    AuthTokenStorage? tokenStorage,
    ApiClient? apiClient,
    AuthTokenRefresher? tokenRefresher,
    http.Client? httpClient,
    String? baseUrl,
  }) {
    final storage = tokenStorage ?? AuthTokenStorage();
    if (tokenStorage != null ||
        apiClient != null ||
        tokenRefresher != null ||
        httpClient != null ||
        baseUrl != null) {
      return CustomerSession._(
        storage,
        apiClient: apiClient,
        tokenRefresher: tokenRefresher,
        httpClient: httpClient,
        baseUrl: baseUrl,
      );
    }
    return _shared ??= CustomerSession._(AuthTokenStorage());
  }

  static CustomerSession? _shared;

  final AuthTokenStorage tokenStorage;
  late final AuthTokenRefresher refresher;
  late final ApiClient apiClient;

  static void resetSharedForTesting() {
    _shared = null;
  }
}

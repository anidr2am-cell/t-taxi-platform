import '../../../core/network/api_exception.dart';
import '../models/auth_user.dart';
import 'customer_session.dart';

class CustomerProfileApiException implements Exception {
  const CustomerProfileApiException(
    this.message, {
    this.statusCode,
    this.errorCode,
    this.field,
  });

  final String message;
  final int? statusCode;
  final String? errorCode;
  final String? field;

  @override
  String toString() => message;
}

class CustomerProfileApiService {
  CustomerProfileApiService({CustomerSession? session})
    : _session = session ?? CustomerSession();

  final CustomerSession _session;

  Future<AuthUser> updateProfile({
    required String name,
    required String phone,
    String? phoneCountryCode,
  }) async {
    final session = await _session.tokenStorage.loadSession();
    if (session == null) {
      throw const CustomerProfileApiException('Sign in is required');
    }

    try {
      final decoded = await _session.apiClient.patchJson(
        '/customer/profile',
        body: {
          'name': name,
          'phone': phone,
          if (phoneCountryCode != null && phoneCountryCode.isNotEmpty)
            'phoneCountryCode': phoneCountryCode,
        },
        bearerToken: session.accessToken,
      );
      final data = decoded['data'];
      if (data is! Map) {
        throw const CustomerProfileApiException('Invalid profile response');
      }
      return AuthUser.fromJson(Map<String, dynamic>.from(data));
    } on ApiException catch (error) {
      throw CustomerProfileApiException(
        error.message ?? 'Profile update failed',
        statusCode: error.statusCode,
        errorCode: error.errorCode,
        field: _fieldFromApiException(error),
      );
    }
  }

  String? _fieldFromApiException(ApiException error) {
    final details = error.details;
    if (details == null) {
      return null;
    }
    final errors = details['errors'];
    if (errors is! List || errors.isEmpty) {
      return null;
    }
    final first = errors.first;
    if (first is Map) {
      final field = first['field'];
      if (field is String && field.isNotEmpty) {
        return field;
      }
    }
    return null;
  }
}

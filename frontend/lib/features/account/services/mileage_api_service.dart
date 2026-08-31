import '../../../core/network/api_exception.dart';
import '../../auth/services/customer_api_errors.dart';
import '../../auth/services/customer_session.dart';

class MileageApiException implements Exception {
  const MileageApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class MileageBalanceResult {
  const MileageBalanceResult({required this.balance});

  final int balance;
}

class MileageApiService {
  MileageApiService({
    CustomerSession? session,
  }) : _session = session ?? CustomerSession();

  final CustomerSession _session;

  Future<MileageBalanceResult> getMileageBalance() async {
    final session = await _session.tokenStorage.loadSession();
    if (session == null) {
      throw const MileageApiException('Authentication required');
    }

    try {
      final decoded = await _session.apiClient.getJson(
        '/customer/mileage',
        bearerToken: session.accessToken,
      );
      final data = decoded['data'] as Map?;
      if (data == null) {
        throw const MileageApiException('Invalid mileage response');
      }
      return MileageBalanceResult(
        balance: data['balance'] as int? ?? 0,
      );
    } on ApiException catch (error) {
      throw MileageApiException(
        customerApiErrorMessage(error, fallback: 'Unable to load mileage balance'),
        statusCode: error.statusCode,
      );
    }
  }
}

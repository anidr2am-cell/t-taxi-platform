import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/storage/secure_token_storage.dart';

abstract interface class DispatchDataSource {
  Future<Map<String, dynamic>> getStatus();
  Future<Map<String, dynamic>> goOnline();
  Future<Map<String, dynamic>> goOffline();
  Future<Map<String, dynamic>> getOpenCalls();
  Future<Map<String, dynamic>> claimOpenCall(
    String bookingNumber,
    int driverVehicleId,
  );
  Future<Map<String, dynamic>> lockUrgentCall(String bookingNumber);
  Future<Map<String, dynamic>> submitUrgentEta(
    String bookingNumber,
    int etaMinutes,
  );
}

class DispatchApi implements DispatchDataSource {
  const DispatchApi({required ApiClient client, required TokenStorage storage})
    : _client = client,
      _storage = storage;

  final ApiClient _client;
  final TokenStorage _storage;

  @override
  Future<Map<String, dynamic>> getStatus() async => _client.getJson(
    '/api/v1/driver/status',
    bearerToken: await _accessToken(),
  );

  @override
  Future<Map<String, dynamic>> goOnline() async => _client.postJson(
    '/api/v1/driver/online',
    bearerToken: await _accessToken(),
  );

  @override
  Future<Map<String, dynamic>> goOffline() async => _client.postJson(
    '/api/v1/driver/offline',
    bearerToken: await _accessToken(),
  );

  @override
  Future<Map<String, dynamic>> getOpenCalls() async => _client.getJson(
    '/api/v1/driver/calls/open',
    bearerToken: await _accessToken(),
  );

  @override
  Future<Map<String, dynamic>> claimOpenCall(
    String bookingNumber,
    int driverVehicleId,
  ) async {
    if (!RegExp(r'^TX\d{12}$').hasMatch(bookingNumber) ||
        driverVehicleId <= 0) {
      throw const ApiException(ApiFailureKind.invalidResponse);
    }
    return _client.postJson(
      '/api/v1/driver/calls/${Uri.encodeComponent(bookingNumber)}/claim',
      bearerToken: await _accessToken(),
      body: {'driverVehicleId': driverVehicleId},
    );
  }

  @override
  Future<Map<String, dynamic>> lockUrgentCall(String bookingNumber) async {
    _validateBookingNumber(bookingNumber);
    return _client.postJson(
      '/api/v1/driver/urgent-calls/${Uri.encodeComponent(bookingNumber)}/lock',
      bearerToken: await _accessToken(),
    );
  }

  @override
  Future<Map<String, dynamic>> submitUrgentEta(
    String bookingNumber,
    int etaMinutes,
  ) async {
    _validateBookingNumber(bookingNumber);
    if (etaMinutes < 1) {
      throw const ApiException(ApiFailureKind.validation);
    }
    return _client.postJson(
      '/api/v1/driver/urgent-calls/${Uri.encodeComponent(bookingNumber)}/eta',
      bearerToken: await _accessToken(),
      body: {'etaMinutes': etaMinutes},
    );
  }

  void _validateBookingNumber(String bookingNumber) {
    if (!RegExp(r'^TX\d{12}$').hasMatch(bookingNumber)) {
      throw const ApiException(ApiFailureKind.validation);
    }
  }

  Future<String> _accessToken() async {
    final token = (await _storage.read())?.accessToken;
    if (token == null || token.isEmpty) {
      throw const ApiException(ApiFailureKind.unauthorized);
    }
    return token;
  }
}

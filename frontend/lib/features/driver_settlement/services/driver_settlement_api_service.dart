import 'package:http_parser/http_parser.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../driver/services/driver_session.dart';

class DriverSettlementApiException implements Exception {
  const DriverSettlementApiException(
    this.message, {
    this.errorCode,
    this.statusCode,
  });

  final String message;
  final String? errorCode;
  final int? statusCode;

  @override
  String toString() => message;
}

class DriverSettlementApiService {
  DriverSettlementApiService({DriverSession? session})
    : _session = session ?? DriverSession();

  final DriverSession _session;

  Future<dynamic> _get(String path) async {
    final token = await _requireAccessToken();
    try {
      final decoded = await _session.apiClient.getJson(
        path,
        bearerToken: token,
      );
      return decoded['data'];
    } on ApiException catch (err) {
      throw await _mapApiException(err);
    }
  }

  Future<dynamic> _postFile(String path, List<int> bytes, String filename) async {
    final token = await _requireAccessToken();
    final ext = filename.contains('.') ? filename.split('.').last.toLowerCase() : '';
    final mimeType = switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'pdf' => 'application/pdf',
      _ => 'application/octet-stream',
    };
    try {
      final decoded = await _session.apiClient.postMultipart(
        path,
        bearerToken: token,
        files: [
          ApiMultipartFile(
            field: 'file',
            filename: filename,
            bytes: bytes,
            contentType: mimeType,
          ),
        ],
      );
      return decoded['data'];
    } on ApiException catch (err) {
      throw await _mapApiException(err);
    }
  }

  Future<String> _requireAccessToken() async {
    final token = await _session.tokenStorage.readAccessToken();
    if (token == null || token.isEmpty) {
      throw const DriverSettlementApiException('Please log in again');
    }
    return token;
  }

  Future<DriverSettlementApiException> _mapApiException(ApiException err) async {
    if (err.kind == ApiFailureKind.unauthorized) {
      await _session.expireSession();
    }
    return DriverSettlementApiException(
      err.message ?? 'Request failed',
      errorCode: err.errorCode,
      statusCode: err.statusCode,
    );
  }

  Future<List<dynamic>> listSettlements() async {
    final data = await _get('/driver/settlements');
    if (data is Map) return data['items'] as List<dynamic>? ?? [];
    return [];
  }

  Future<Map<String, dynamic>> getSettlement(String bookingNumber) async {
    final data = await _get('/driver/settlements/$bookingNumber');
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> uploadReceipt(
    String bookingNumber,
    List<int> bytes,
    String filename,
  ) async {
    final data = await _postFile(
      '/driver/settlements/$bookingNumber/receipt',
      bytes,
      filename,
    );
    return Map<String, dynamic>.from(data as Map);
  }
}

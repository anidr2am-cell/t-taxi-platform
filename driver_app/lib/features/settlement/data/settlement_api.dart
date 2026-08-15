import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/storage/secure_token_storage.dart';
import 'settlement_models.dart';

abstract interface class SettlementDataSource {
  Future<List<SettlementItem>> listSettlements();
  Future<SettlementItem> getSettlement(String bookingNumber);
  Future<SettlementItem> uploadReceipt(
    String bookingNumber,
    SettlementUploadFile file, {
    required String idempotencyKey,
  });
  Future<List<int>> downloadReceipt(String path);
}

class SettlementApi implements SettlementDataSource {
  const SettlementApi({
    required ApiClient client,
    required TokenStorage storage,
  }) : _client = client,
       _storage = storage;

  final ApiClient _client;
  final TokenStorage _storage;

  @override
  Future<List<SettlementItem>> listSettlements() async {
    final data = _data(
      await _client.getJson(
        '/api/v1/driver/settlements',
        bearerToken: await _token(),
      ),
    );
    final items = data['items'];
    if (items is! List) {
      throw const ApiException(ApiFailureKind.invalidResponse);
    }
    return items
        .map(
          (item) =>
              SettlementItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }

  @override
  Future<SettlementItem> getSettlement(String bookingNumber) async {
    final data = _data(
      await _client.getJson(
        '/api/v1/driver/settlements/$bookingNumber',
        bearerToken: await _token(),
      ),
    );
    return SettlementItem.fromJson(data);
  }

  @override
  Future<SettlementItem> uploadReceipt(
    String bookingNumber,
    SettlementUploadFile file, {
    required String idempotencyKey,
  }) async {
    _validateFile(file);
    final envelope = await _client.postMultipart(
      '/api/v1/driver/settlements/$bookingNumber/receipt',
      bearerToken: await _token(),
      headers: {'Idempotency-Key': idempotencyKey},
      files: [
        ApiMultipartFile(
          field: 'file',
          filename: file.filename,
          bytes: file.bytes,
          contentType: _contentTypeFor(file.filename),
        ),
      ],
    );
    return SettlementItem.fromJson(_data(envelope));
  }

  @override
  Future<List<int>> downloadReceipt(String path) async {
    return _client.getBytes(path, bearerToken: await _token());
  }

  void _validateFile(SettlementUploadFile file) {
    final name = file.filename.toLowerCase();
    const allowed = ['.jpg', '.jpeg', '.png', '.pdf'];
    if (file.bytes.isEmpty || !allowed.any(name.endsWith)) {
      throw const ApiException(ApiFailureKind.invalidFileType);
    }
  }

  String _contentTypeFor(String filename) {
    final name = filename.toLowerCase();
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.pdf')) return 'application/pdf';
    return 'application/octet-stream';
  }

  Map<String, dynamic> _data(Map<String, dynamic> envelope) {
    final data = envelope['data'];
    if (data is! Map) throw const ApiException(ApiFailureKind.invalidResponse);
    return Map<String, dynamic>.from(data);
  }

  Future<String> _token() async {
    final token = (await _storage.read())?.accessToken;
    if (token == null || token.isEmpty) {
      throw const ApiException(ApiFailureKind.unauthorized);
    }
    return token;
  }
}

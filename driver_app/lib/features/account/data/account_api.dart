import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/storage/secure_token_storage.dart';
import 'account_models.dart';

abstract interface class AccountDataSource {
  Future<DriverProfile> getProfile();
  Future<DriverProfile> updateProfile(Map<String, dynamic> changes);
  Future<void> uploadAvatar(AccountUploadFile file);
  Future<void> uploadVehiclePhoto(AccountUploadFile file);
  Future<List<DriverVehicle>> getVehicles();
  Future<DriverVehicle> createVehicle(VehicleCreateRequest request);
  Future<RatingSummary> getRatingSummary();
  Future<List<VehicleTypeOption>> getVehicleTypes();
  Future<List<int>> loadAsset(String path);
}

class AccountApi implements AccountDataSource {
  const AccountApi({required ApiClient client, required TokenStorage storage})
    : _client = client,
      _storage = storage;

  final ApiClient _client;
  final TokenStorage _storage;

  @override
  Future<List<int>> loadAsset(String path) async {
    final supplied = Uri.tryParse(path);
    final isAbsolute =
        supplied != null && supplied.hasScheme && supplied.host.isNotEmpty;
    return _client.getBytes(
      path,
      bearerToken: isAbsolute ? null : await _token(),
    );
  }

  @override
  Future<DriverProfile> getProfile() async => DriverProfile.fromJson(
    _data(
      await _client.getJson(
        '/api/v1/driver/profile',
        bearerToken: await _token(),
      ),
    ),
  );

  @override
  Future<DriverProfile> updateProfile(Map<String, dynamic> changes) async {
    if (changes.isEmpty) {
      throw const ApiException(ApiFailureKind.validation);
    }
    return DriverProfile.fromJson(
      _data(
        await _client.patchJson(
          '/api/v1/driver/profile',
          bearerToken: await _token(),
          body: changes,
        ),
      ),
    );
  }

  @override
  Future<void> uploadAvatar(AccountUploadFile file) =>
      _uploadProfileFile('/api/v1/driver/profile/avatar', file);

  @override
  Future<void> uploadVehiclePhoto(AccountUploadFile file) =>
      _uploadProfileFile('/api/v1/driver/profile/vehicle-photo', file);

  Future<void> _uploadProfileFile(String path, AccountUploadFile file) async {
    _validateExtension(file, allowPdf: false);
    await _client.postMultipart(
      path,
      bearerToken: await _token(),
      files: [
        ApiMultipartFile(
          field: 'file',
          filename: file.filename,
          bytes: file.bytes,
        ),
      ],
    );
  }

  @override
  Future<List<DriverVehicle>> getVehicles() async {
    final data = _data(
      await _client.getJson(
        '/api/v1/driver/vehicles',
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
              DriverVehicle.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }

  @override
  Future<DriverVehicle> createVehicle(VehicleCreateRequest request) async {
    _validateVehicleRequest(request);
    final fields = <String, String>{
      'vehicleTypeId': request.vehicleTypeId.toString(),
      'plateNumber': request.plateNumber.trim(),
      if (request.modelName?.trim().isNotEmpty == true)
        'modelName': request.modelName!.trim(),
      if (request.color?.trim().isNotEmpty == true)
        'color': request.color!.trim(),
    };
    final files = <ApiMultipartFile>[
      for (final file in request.vehiclePhotos)
        ApiMultipartFile(
          field: 'vehiclePhotos',
          filename: file.filename,
          bytes: file.bytes,
        ),
      ApiMultipartFile(
        field: 'insuranceCertificate',
        filename: request.insuranceCertificate.filename,
        bytes: request.insuranceCertificate.bytes,
      ),
      ApiMultipartFile(
        field: 'vehicleRegistration',
        filename: request.vehicleRegistration.filename,
        bytes: request.vehicleRegistration.bytes,
      ),
    ];
    final envelope = await _client.postMultipart(
      '/api/v1/driver/vehicles',
      bearerToken: await _token(),
      fields: fields,
      files: files,
    );
    return DriverVehicle.fromJson(_data(envelope));
  }

  @override
  Future<RatingSummary> getRatingSummary() async => RatingSummary.fromJson(
    _data(
      await _client.getJson(
        '/api/v1/driver/rating-summary',
        bearerToken: await _token(),
      ),
    ),
  );

  @override
  Future<List<VehicleTypeOption>> getVehicleTypes() async {
    final envelope = await _client.getJson(
      '/api/v1/vehicles/types',
      bearerToken: await _token(),
    );
    final data = envelope['data'];
    if (data is! List) throw const ApiException(ApiFailureKind.invalidResponse);
    return data
        .map(
          (item) => VehicleTypeOption.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .where((item) => item.id > 0)
        .toList(growable: false);
  }

  void _validateVehicleRequest(VehicleCreateRequest request) {
    final plate = request.plateNumber.trim();
    if (request.vehicleTypeId <= 0 ||
        plate.length < 2 ||
        plate.length > 20 ||
        request.vehiclePhotos.length < 3 ||
        request.vehiclePhotos.length > 6 ||
        (request.modelName?.trim().length ?? 0) > 100 ||
        (request.color?.trim().length ?? 0) > 30) {
      throw const ApiException(ApiFailureKind.validation);
    }
    for (final photo in request.vehiclePhotos) {
      _validateExtension(photo, allowPdf: false);
    }
    _validateExtension(request.insuranceCertificate, allowPdf: true);
    _validateExtension(request.vehicleRegistration, allowPdf: true);
  }

  void _validateExtension(AccountUploadFile file, {required bool allowPdf}) {
    final name = file.filename.toLowerCase();
    final allowed = allowPdf
        ? const ['.jpg', '.jpeg', '.png', '.webp', '.pdf']
        : const ['.jpg', '.jpeg', '.png', '.webp'];
    if (file.bytes.isEmpty || !allowed.any(name.endsWith)) {
      throw const ApiException(ApiFailureKind.invalidFileType);
    }
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

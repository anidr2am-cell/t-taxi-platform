import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import 'driver_application_models.dart';

abstract interface class DriverApplicationDataSource {
  Future<List<DriverApplicationVehicleType>> listVehicleTypes();
  Future<DriverApplicationReceipt> submitApplication(
    DriverApplicationDraft draft,
  );
  Future<DriverApplicationStatusResult> getApplicationStatus({
    required String applicationNumber,
    required String token,
  });
}

class DriverApplicationApi implements DriverApplicationDataSource {
  DriverApplicationApi({required ApiClient client}) : _client = client;

  final ApiClient _client;

  @override
  Future<List<DriverApplicationVehicleType>> listVehicleTypes() async {
    try {
      final envelope = await _client.getJson('/api/v1/vehicles/types');
      final data = envelope['data'];
      if (data is! List) {
        throw const DriverApplicationApiException(
          DriverApplicationFailureKind.invalidResponse,
        );
      }
      return data
          .map(
            (item) => DriverApplicationVehicleType.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .where((item) => item.code.isNotEmpty)
          .toList(growable: false);
    } on ApiException catch (error) {
      throw _fromApiException(error);
    }
  }

  @override
  Future<DriverApplicationReceipt> submitApplication(
    DriverApplicationDraft draft,
  ) async {
    final issues = DriverApplicationFormValidator.validate(draft);
    if (issues.isNotEmpty) {
      throw const DriverApplicationApiException(
        DriverApplicationFailureKind.validation,
      );
    }

    for (final photo in draft.files.vehiclePhotos) {
      if (!DriverApplicationFormValidator.isAllowedFilename(
        photo.filename,
        imageOnly: true,
      )) {
        throw const DriverApplicationApiException(
          DriverApplicationFailureKind.invalidFileType,
        );
      }
    }
    for (final file in [
      draft.files.lineQr,
      draft.files.insuranceCertificate,
      draft.files.vehicleRegistration,
      draft.files.taxCertificate,
    ]) {
      if (file == null) continue;
      final imageOnly = identical(file, draft.files.lineQr);
      if (!DriverApplicationFormValidator.isAllowedFilename(
        file.filename,
        imageOnly: imageOnly,
      )) {
        throw const DriverApplicationApiException(
          DriverApplicationFailureKind.invalidFileType,
        );
      }
    }

    try {
      final envelope = await _client.postMultipart(
        '/api/v1/driver-applications',
        fields: draft.toMultipartFields(),
        files: draft.toMultipartFiles(),
      );
      return DriverApplicationReceipt.fromJson(_data(envelope));
    } on ApiException catch (error) {
      throw _fromApiException(error);
    }
  }

  @override
  Future<DriverApplicationStatusResult> getApplicationStatus({
    required String applicationNumber,
    required String token,
  }) async {
    final number = applicationNumber.trim();
    final statusToken = token.trim();
    if (number.isEmpty || statusToken.isEmpty) {
      throw const DriverApplicationApiException(
        DriverApplicationFailureKind.validation,
      );
    }

    try {
      final envelope = await _client.getJson(
        '/api/v1/driver-applications/status',
        queryParameters: {
          'applicationNumber': number,
          'token': statusToken,
        },
      );
      return DriverApplicationStatusResult.fromJson(_data(envelope));
    } on ApiException catch (error) {
      throw _fromApiException(error);
    }
  }

  Map<String, dynamic> _data(Map<String, dynamic> envelope) {
    final data = envelope['data'];
    if (data is! Map) {
      throw const DriverApplicationApiException(
        DriverApplicationFailureKind.invalidResponse,
      );
    }
    return Map<String, dynamic>.from(data);
  }

  DriverApplicationApiException _fromApiException(ApiException error) {
    final fieldErrors = {
      for (final item in error.errors)
        if (item['field']?.toString().isNotEmpty == true &&
            item['message']?.toString().isNotEmpty == true)
          item['field']!.toString(): item['message']!.toString(),
    };

    final kind = switch (error.kind) {
      ApiFailureKind.validation => DriverApplicationFailureKind.validation,
      ApiFailureKind.invalidFileType =>
        DriverApplicationFailureKind.invalidFileType,
      ApiFailureKind.fileTooLarge => DriverApplicationFailureKind.fileTooLarge,
      ApiFailureKind.vehiclePlateAlreadyRegistered =>
        DriverApplicationFailureKind.plateConflict,
      ApiFailureKind.notFound => DriverApplicationFailureKind.notFound,
      ApiFailureKind.conflict => _conflictKind(fieldErrors),
      ApiFailureKind.unavailable => DriverApplicationFailureKind.unavailable,
      ApiFailureKind.timeout => DriverApplicationFailureKind.timeout,
      ApiFailureKind.server => DriverApplicationFailureKind.server,
      ApiFailureKind.invalidResponse =>
        DriverApplicationFailureKind.invalidResponse,
      _ => DriverApplicationFailureKind.unknown,
    };

    return DriverApplicationApiException(
      kind,
      statusCode: error.statusCode,
      fieldErrors: fieldErrors,
    );
  }

  DriverApplicationFailureKind _conflictKind(Map<String, String> fieldErrors) {
    if (fieldErrors.containsKey('phone')) {
      return DriverApplicationFailureKind.phoneConflict;
    }
    if (fieldErrors.containsKey('vehiclePlateNumber')) {
      return DriverApplicationFailureKind.plateConflict;
    }
    return DriverApplicationFailureKind.duplicateApplication;
  }
}

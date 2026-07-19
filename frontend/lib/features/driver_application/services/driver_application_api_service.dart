import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_config.dart';
import '../models/driver_application_models.dart';

class DriverApplicationApiException implements Exception {
  const DriverApplicationApiException(
    this.message, {
    this.errorCode,
    this.statusCode,
    this.fieldErrors = const {},
  });

  final String message;
  final String? errorCode;
  final int? statusCode;
  final Map<String, String> fieldErrors;

  @override
  String toString() => message;
}

class DriverApplicationApiService {
  DriverApplicationApiService({
    http.Client? client,
    String? baseUrl,
    Future<String?> Function()? adminTokenProvider,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? AppConfig.apiBaseUrl,
       _adminTokenProvider = adminTokenProvider;

  final http.Client _client;
  final String _baseUrl;
  final Future<String?> Function()? _adminTokenProvider;

  String get _base => '$_baseUrl/api/v1';

  static const _imageExtensions = {'jpg', 'jpeg', 'png'};
  static const _documentExtensions = {'jpg', 'jpeg', 'png', 'pdf'};

  dynamic _decodeResponseBody(http.Response response) {
    if (response.body.isEmpty) return null;
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    final trimmed = response.body.trimLeft();
    final looksLikeJson = trimmed.startsWith('{') || trimmed.startsWith('[');
    if (!contentType.contains('application/json') && !looksLikeJson) {
      return null;
    }
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return null;
    }
  }

  DriverApplicationApiException _exceptionForResponse(
    http.Response response,
    dynamic decoded,
  ) {
    final statusCode = response.statusCode;
    final errorCode = decoded is Map
        ? (decoded['error_code'] ?? decoded['code']) as String?
        : null;
    final message = decoded is Map
        ? decoded['message'] as String? ?? _fallbackMessage(statusCode)
        : _fallbackMessage(statusCode);
    return DriverApplicationApiException(
      message,
      errorCode: errorCode ?? _fallbackErrorCode(statusCode),
      statusCode: statusCode,
      fieldErrors: _fieldErrors(decoded),
    );
  }

  String _fallbackErrorCode(int statusCode) {
    if (statusCode == 413) return 'FILE_TOO_LARGE';
    if (statusCode == 502 || statusCode == 503 || statusCode == 504) {
      return 'SERVER_UNAVAILABLE';
    }
    return 'REQUEST_FAILED';
  }

  String _fallbackMessage(int statusCode) {
    if (statusCode == 413) return 'Uploaded files are too large';
    if (statusCode == 502 || statusCode == 503 || statusCode == 504) {
      return 'Server connection failed';
    }
    return 'Request failed';
  }

  String _extension(String filename) {
    final safeName = filename
        .split(RegExp(r'[?#]'))
        .first
        .split(RegExp(r'[\\/]'))
        .last;
    final dot = safeName.lastIndexOf('.');
    if (dot < 0 || dot == safeName.length - 1) return '';
    return safeName.substring(dot + 1).toLowerCase();
  }

  MediaType? _contentTypeFor(String filename, {required bool imageOnly}) {
    final ext = _extension(filename);
    final allowed = imageOnly ? _imageExtensions : _documentExtensions;
    if (!allowed.contains(ext)) return null;
    final mimeType = switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'pdf' => 'application/pdf',
      _ => 'application/octet-stream',
    };
    return MediaType.parse(mimeType);
  }

  Map<String, String> _fieldErrors(dynamic decoded) {
    if (decoded is! Map || decoded['errors'] is! List) return const {};
    final result = <String, String>{};
    for (final item in decoded['errors'] as List) {
      if (item is! Map) continue;
      final field = item['field']?.toString();
      final message = item['message']?.toString();
      if (field == null ||
          field.isEmpty ||
          message == null ||
          message.isEmpty) {
        continue;
      }
      result.putIfAbsent(field, () => message);
    }
    return result;
  }

  Future<String?> _adminToken() async {
    final provider = _adminTokenProvider;
    if (provider != null) return provider();
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('admin_access_token');
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    bool admin = false,
  }) async {
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (admin) {
      final token = await _adminToken();
      if (token == null || token.isEmpty) {
        throw const DriverApplicationApiException(
          'Please log in',
          statusCode: 401,
        );
      }
      headers['Authorization'] = 'Bearer $token';
    }

    final response = method == 'GET'
        ? await _client.get(uri, headers: headers)
        : await _client.post(
            uri,
            headers: headers,
            body: jsonEncode(body ?? {}),
          );

    final decoded = _decodeResponseBody(response);
    if (response.statusCode >= 400) {
      throw _exceptionForResponse(response, decoded);
    }
    if (response.body.isNotEmpty && decoded == null) {
      throw _exceptionForResponse(response, decoded);
    }

    if (decoded is Map && decoded.containsKey('data')) return decoded['data'];
    return decoded;
  }

  Future<dynamic> _multipart(
    String path,
    DriverApplicationDraft draft, {
    String? token,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$_base$path'));
    request.headers['Accept'] = 'application/json';
    final fields = draft.toJson().map(
      (key, value) =>
          MapEntry(key, value is List ? value.join(',') : '${value ?? ''}'),
    );
    request.fields.addAll(fields);
    if (token != null) request.fields['token'] = token;

    Future<void> add(
      String field,
      DriverApplicationUploadFile? file, {
      required bool imageOnly,
    }) async {
      if (file == null) return;
      final contentType = _contentTypeFor(file.name, imageOnly: imageOnly);
      if (contentType == null) {
        throw DriverApplicationApiException(
          'Invalid file type',
          errorCode: 'INVALID_FILE_TYPE',
          statusCode: 400,
        );
      }
      request.files.add(
        http.MultipartFile.fromBytes(
          field,
          file.bytes,
          filename: file.name,
          contentType: contentType,
        ),
      );
    }

    await add('lineQr', draft.files.lineQr, imageOnly: true);
    for (final file in draft.files.vehiclePhotos) {
      await add('vehiclePhotos', file, imageOnly: true);
    }
    await add(
      'insuranceCertificate',
      draft.files.insuranceCertificate,
      imageOnly: false,
    );
    await add(
      'vehicleRegistration',
      draft.files.vehicleRegistration,
      imageOnly: false,
    );
    await add('taxCertificate', draft.files.taxCertificate, imageOnly: false);

    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    final decoded = _decodeResponseBody(response);
    if (response.statusCode >= 400) {
      throw _exceptionForResponse(response, decoded);
    }
    if (response.body.isNotEmpty && decoded == null) {
      throw _exceptionForResponse(response, decoded);
    }
    if (decoded is Map && decoded.containsKey('data')) return decoded['data'];
    return decoded;
  }

  Future<DriverApplicationReceipt> submitApplication(
    DriverApplicationDraft draft,
  ) async {
    final data = await _multipart('/driver-applications', draft);
    return DriverApplicationReceipt.fromJson(
      Map<String, dynamic>.from(data as Map),
    );
  }

  Future<DriverApplicationStatusResult> getApplicationStatus({
    required String applicationNumber,
    required String token,
  }) async {
    final data = await _request(
      'GET',
      '/driver-applications/status',
      query: {'applicationNumber': applicationNumber, 'token': token},
    );
    return DriverApplicationStatusResult.fromJson(
      Map<String, dynamic>.from(data as Map),
    );
  }

  Future<DriverApplicationReceipt> resubmitApplication({
    required String applicationNumber,
    required String token,
    required DriverApplicationDraft draft,
  }) async {
    final data = await _multipart(
      '/driver-applications/$applicationNumber/resubmit',
      draft,
      token: token,
    );
    return DriverApplicationReceipt.fromJson(
      Map<String, dynamic>.from(data as Map),
    );
  }

  Future<List<DriverApplicationVehicleType>> listVehicleTypes() async {
    final data = await _request('GET', '/vehicles/types');
    final items = data is List
        ? data
        : data is Map
        ? data['items'] as List<dynamic>? ?? const []
        : const [];
    return items
        .map(
          (item) => DriverApplicationVehicleType.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .where((item) => item.code.isNotEmpty)
        .toList(growable: false);
  }

  Future<DriverApplicationAdminListResult> listAdminApplications({
    String? view,
    String? status,
    String? countryCode,
    String? vehicleTypeCode,
    String? dateFrom,
    String? dateTo,
    String? search,
    int page = 1,
    int limit = 20,
  }) async {
    final query = <String, String>{'page': '$page', 'limit': '$limit'};
    if (view != null && view.isNotEmpty) query['view'] = view;
    if (status != null && status.isNotEmpty) query['status'] = status;
    if (countryCode != null && countryCode.isNotEmpty) {
      query['countryCode'] = countryCode;
    }
    if (vehicleTypeCode != null && vehicleTypeCode.isNotEmpty) {
      query['vehicleTypeCode'] = vehicleTypeCode;
    }
    if (dateFrom != null && dateFrom.isNotEmpty) query['dateFrom'] = dateFrom;
    if (dateTo != null && dateTo.isNotEmpty) query['dateTo'] = dateTo;
    if (search != null && search.isNotEmpty) query['search'] = search;

    final data = await _request(
      'GET',
      '/admin/driver-applications',
      query: query,
      admin: true,
    );
    return DriverApplicationAdminListResult.fromJson(
      Map<String, dynamic>.from(data as Map),
    );
  }

  Future<DriverApplicationAdminDetail> getAdminApplicationDetail(int id) async {
    final data = await _request(
      'GET',
      '/admin/driver-applications/$id',
      admin: true,
    );
    return DriverApplicationAdminDetail.fromJson(
      Map<String, dynamic>.from(data as Map),
    );
  }

  Future<Map<String, dynamic>> approveApplication(int id) async {
    final data = await _request(
      'POST',
      '/admin/driver-applications/$id/approve',
      body: {},
      admin: true,
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> rejectApplication(
    int id, {
    required String rejectionReason,
    String? adminNote,
  }) async {
    final data = await _request(
      'POST',
      '/admin/driver-applications/$id/reject',
      body: {
        'rejectionReason': rejectionReason,
        if (adminNote != null && adminNote.trim().isNotEmpty)
          'adminNote': adminNote.trim(),
      },
      admin: true,
    );
    return Map<String, dynamic>.from(data as Map);
  }
}

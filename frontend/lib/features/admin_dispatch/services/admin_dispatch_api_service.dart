import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_config.dart';

class AdminDispatchApiException implements Exception {
  const AdminDispatchApiException(
    this.message, {
    this.errorCode,
    this.errors = const [],
  });

  final String message;
  final String? errorCode;
  final List<AdminDispatchApiErrorDetail> errors;

  @override
  String toString() => message;
}

class AdminDispatchApiErrorDetail {
  const AdminDispatchApiErrorDetail({
    required this.field,
    this.type,
    this.source,
    this.message,
  });

  final String field;
  final String? type;
  final String? source;
  final String? message;

  factory AdminDispatchApiErrorDetail.fromJson(Map<String, dynamic> json) {
    return AdminDispatchApiErrorDetail(
      field: json['field'] as String? ?? '',
      type: json['type'] as String?,
      source: json['source'] as String?,
      message: json['message'] as String?,
    );
  }
}

class AdminDispatchApiService {
  const AdminDispatchApiService({http.Client? client, String? baseUrl})
    : _client = client,
      _baseUrl = baseUrl;

  static const _tokenKey = 'admin_access_token';
  final http.Client? _client;
  final String? _baseUrl;

  String get _base => '${_baseUrl ?? AppConfig.apiBaseUrl}/api/v1';

  Future<String?> getSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  Future<void> login({required String email, required String password}) async {
    final response = await http.post(
      Uri.parse('$_base/auth/login'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'email': email, 'password': password}),
    );
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw AdminDispatchApiException(
        decoded['message'] as String? ?? 'Login failed',
      );
    }
    final data = Map<String, dynamic>.from(decoded['data'] as Map);
    final user = Map<String, dynamic>.from(data['user'] as Map);
    final role = user['role'] as String?;
    if (role != 'ADMIN' && role != 'SUPER_ADMIN') {
      throw const AdminDispatchApiException('Admin account required');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, data['accessToken'] as String);
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final token = await getSavedToken();
    if (token == null || token.isEmpty) {
      throw const AdminDispatchApiException('Please log in');
    }

    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final headers = {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      if (body != null) 'Content-Type': 'application/json',
    };

    final client = _client;
    final encodedBody = body != null ? jsonEncode(body) : null;
    Future<http.Response> sendRequest() {
      switch (method) {
        case 'GET':
          return client == null
              ? http.get(uri, headers: headers)
              : client.get(uri, headers: headers);
        case 'PATCH':
          return client == null
              ? http.patch(uri, headers: headers, body: encodedBody)
              : client.patch(uri, headers: headers, body: encodedBody);
        default:
          return client == null
              ? http.post(uri, headers: headers, body: encodedBody ?? '{}')
              : client.post(
                  uri,
                  headers: headers,
                  body: encodedBody ?? '{}',
                );
      }
    }

    final response = await sendRequest();

    final decoded = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      if (response.statusCode == 401) await logout();
      final message = decoded is Map
          ? decoded['message'] as String? ?? 'Request failed'
          : 'Request failed';
      final errors = decoded is Map && decoded['errors'] is List
          ? (decoded['errors'] as List)
                .whereType<Map>()
                .map(
                  (item) => AdminDispatchApiErrorDetail.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false)
          : const <AdminDispatchApiErrorDetail>[];
      throw AdminDispatchApiException(
        message,
        errorCode: decoded is Map ? decoded['error_code'] as String? : null,
        errors: errors,
      );
    }

    if (decoded is Map && decoded.containsKey('data')) {
      return decoded['data'];
    }
    return decoded;
  }

  Future<Map<String, dynamic>> listBookings({
    String? view,
    String? search,
    String? status,
    String? assignmentState,
    String? serviceDateFrom,
    String? serviceDateTo,
    String? serviceType,
    String? origin,
    String? destination,
    String? settlementStatus,
    bool? lowRating,
    bool? unassigned,
    bool? hasInquiry,
    bool? archived,
    int page = 1,
    int limit = 20,
  }) async {
    final query = <String, String>{'page': '$page', 'limit': '$limit'};
    if (view != null && view.isNotEmpty) query['view'] = view;
    if (search != null && search.isNotEmpty) query['search'] = search;
    if (status != null && status.isNotEmpty) query['status'] = status;
    if (assignmentState != null && assignmentState.isNotEmpty) {
      query['assignmentState'] = assignmentState;
    }
    if (serviceDateFrom != null && serviceDateFrom.isNotEmpty) {
      query['serviceDateFrom'] = serviceDateFrom;
    }
    if (serviceDateTo != null && serviceDateTo.isNotEmpty) {
      query['serviceDateTo'] = serviceDateTo;
    }
    if (serviceType != null && serviceType.isNotEmpty) {
      query['serviceType'] = serviceType;
    }
    if (origin != null && origin.isNotEmpty) query['origin'] = origin;
    if (destination != null && destination.isNotEmpty) {
      query['destination'] = destination;
    }
    if (settlementStatus != null && settlementStatus.isNotEmpty) {
      query['settlementStatus'] = settlementStatus;
    }
    if (lowRating == true) query['lowRating'] = 'true';
    if (unassigned == true) query['unassigned'] = 'true';
    if (hasInquiry == true) query['hasInquiry'] = 'true';
    if (archived == true) query['archived'] = 'true';
    final data = await _request('GET', '/admin/bookings', query: query);
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> getBookingsSummary() async {
    final data = await _request('GET', '/admin/bookings/summary');
    return Map<String, dynamic>.from(data as Map);
  }

  static dynamic _deepNormalizeJson(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(
        value.map(
          (key, nested) =>
              MapEntry(key.toString(), _deepNormalizeJson(nested)),
        ),
      );
    }
    if (value is List) {
      return value.map(_deepNormalizeJson).toList(growable: false);
    }
    return value;
  }

  Future<Map<String, dynamic>> getBookingDetail(String bookingNumber) async {
    final data = await _request('GET', '/admin/bookings/$bookingNumber');
    if (data is! Map) {
      throw AdminDispatchApiException('Invalid booking detail response');
    }
    return Map<String, dynamic>.from(
      _deepNormalizeJson(data) as Map,
    );
  }

  Future<Map<String, dynamic>> listBookingNotes(
    String bookingNumber, {
    int page = 1,
    int limit = 20,
  }) async {
    final data = await _request(
      'GET',
      '/admin/bookings/$bookingNumber/notes',
      query: {'page': '$page', 'limit': '$limit'},
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> addBookingNote(
    String bookingNumber,
    String text,
  ) async {
    final data = await _request(
      'POST',
      '/admin/bookings/$bookingNumber/notes',
      body: {'text': text},
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> processNoShow(
    String bookingNumber, {
    required num penaltyAmount,
    required String reason,
    String? memo,
  }) async {
    final body = <String, dynamic>{
      'penaltyAmount': penaltyAmount,
      'reason': reason,
    };
    if (memo != null && memo.isNotEmpty) {
      body['memo'] = memo;
    }
    final data = await _request(
      'POST',
      '/admin/bookings/$bookingNumber/no-show',
      body: body,
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<List<dynamic>> listDrivers({
    bool? archived,
    String? bookingNumber,
  }) async {
    final query = <String, String>{};
    if (archived == true) query['archived'] = 'true';
    final booking = bookingNumber?.trim();
    if (booking != null && booking.isNotEmpty) {
      query['bookingNumber'] = booking;
    }
    final data = await _request('GET', '/admin/drivers', query: query);
    if (data is List) return data;
    if (data is Map) return data['items'] as List<dynamic>? ?? [];
    return [];
  }

  Future<Map<String, dynamic>> archiveDrivers(List<int> driverIds) async {
    final data = await _request(
      'POST',
      '/admin/drivers/archive',
      body: {'driverIds': driverIds},
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> restoreDriver(int driverId) async {
    final data = await _request('POST', '/admin/drivers/$driverId/restore');
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> getDriverDeletionPreview(int driverId) async {
    final data = await _request(
      'GET',
      '/admin/drivers/$driverId/deletion-preview',
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> assignDriver(
    String bookingNumber,
    int driverId,
  ) async {
    final data = await _request(
      'POST',
      '/admin/bookings/$bookingNumber/assign-driver',
      body: {'driverId': driverId},
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> verifyContactConnection(
    String bookingNumber,
  ) async {
    final data = await _request(
      'POST',
      '/admin/bookings/$bookingNumber/contact/verify',
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> retryContactDispatch(
    String bookingNumber,
  ) async {
    final data = await _request(
      'POST',
      '/admin/bookings/$bookingNumber/contact/dispatch-retry',
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> reassignDriver(
    String bookingNumber,
    int driverId,
    String reason,
  ) async {
    final data = await _request(
      'POST',
      '/admin/bookings/$bookingNumber/reassign-driver',
      body: {'driverId': driverId, 'reason': reason},
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> unassignDriver(
    String bookingNumber,
    String reason,
  ) async {
    final data = await _request(
      'POST',
      '/admin/bookings/$bookingNumber/unassign-driver',
      body: {'reason': reason},
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> completeTrip(String bookingNumber) async {
    final data = await _request(
      'POST',
      '/admin/bookings/$bookingNumber/complete-trip',
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> getDriverCandidates(String bookingNumber) async {
    final data = await _request(
      'GET',
      '/admin/bookings/$bookingNumber/driver-candidates',
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> autoAssignDriver(
    String bookingNumber, {
    int? driverId,
    bool useTopCandidate = false,
    int? expectedAssignmentVersion,
  }) async {
    final body = <String, dynamic>{};
    if (driverId != null) body['driverId'] = driverId;
    if (useTopCandidate) body['useTopCandidate'] = true;
    if (expectedAssignmentVersion != null) {
      body['expectedAssignmentVersion'] = expectedAssignmentVersion;
    }
    final data = await _request(
      'POST',
      '/admin/bookings/$bookingNumber/auto-assign',
      body: body,
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> reissueQr(
    String bookingNumber,
    String type,
  ) async {
    final data = await _request(
      'POST',
      '/admin/bookings/$bookingNumber/qr/reissue',
      body: {'type': type},
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> archiveBookings(
    List<String> bookingNumbers,
  ) async {
    final data = await _request(
      'POST',
      '/admin/bookings/archive',
      body: {'bookingNumbers': bookingNumbers},
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> restoreBookings(
    List<String> bookingNumbers,
  ) async {
    final data = await _request(
      'POST',
      '/admin/bookings/restore',
      body: {'bookingNumbers': bookingNumbers},
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> createManualBooking({
    required Map<String, dynamic> origin,
    required Map<String, dynamic> destination,
    required String scheduledPickupAt,
    required String vehicleTypeCode,
    required int payoutAmount,
    int? customerChargeAmount,
    required String paymentCollection,
    required Map<String, dynamic> customer,
    String? memo,
    Map<String, dynamic>? passengers,
    Map<String, dynamic>? luggage,
    String? serviceTypeCode,
    bool nameSign = false,
    String? nameSignText,
    bool preferFemaleDriver = false,
    String? originAirportIata,
    Map<String, dynamic>? transfer,
  }) async {
    final body = <String, dynamic>{
      'origin': origin,
      'destination': destination,
      'scheduledPickupAt': scheduledPickupAt,
      'vehicleTypeCode': vehicleTypeCode,
      'payoutAmount': payoutAmount,
      'paymentCollection': paymentCollection,
      'customer': customer,
      'nameSign': nameSign,
      if (nameSign && nameSignText != null && nameSignText.isNotEmpty)
        'nameSignText': nameSignText,
      if (customerChargeAmount != null)
        'customerChargeAmount': customerChargeAmount,
      if (memo != null && memo.isNotEmpty) 'memo': memo,
      if (passengers != null) 'passengers': passengers,
      if (luggage != null) 'luggage': luggage,
      if (serviceTypeCode != null) 'serviceTypeCode': serviceTypeCode,
      'preferFemaleDriver': preferFemaleDriver,
      if (originAirportIata != null && originAirportIata.isNotEmpty)
        'originAirportIata': originAirportIata,
      if (transfer != null) 'transfer': transfer,
    };
    final data = await _request('POST', '/admin/bookings/manual', body: body);
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> updateManualBooking(
    String bookingNumber, {
    required Map<String, dynamic> origin,
    required Map<String, dynamic> destination,
    required String scheduledPickupAt,
    required String vehicleTypeCode,
    required int payoutAmount,
    int? customerChargeAmount,
    required String paymentCollection,
    required Map<String, dynamic> customer,
    String? memo,
    Map<String, dynamic>? passengers,
    Map<String, dynamic>? luggage,
    String? serviceTypeCode,
    bool nameSign = false,
    String? nameSignText,
    bool preferFemaleDriver = false,
    String? originAirportIata,
    Map<String, dynamic>? transfer,
  }) async {
    final payload = <String, dynamic>{
      'origin': origin,
      'destination': destination,
      'scheduledPickupAt': scheduledPickupAt,
      'vehicleTypeCode': vehicleTypeCode,
      'payoutAmount': payoutAmount,
      'paymentCollection': paymentCollection,
      'customer': customer,
      'nameSign': nameSign,
      if (nameSign && nameSignText != null && nameSignText.isNotEmpty)
        'nameSignText': nameSignText,
      if (customerChargeAmount != null)
        'customerChargeAmount': customerChargeAmount,
      if (memo != null && memo.isNotEmpty) 'memo': memo,
      if (passengers != null) 'passengers': passengers,
      if (luggage != null) 'luggage': luggage,
      if (serviceTypeCode != null) 'serviceTypeCode': serviceTypeCode,
      'preferFemaleDriver': preferFemaleDriver,
      if (originAirportIata != null && originAirportIata.isNotEmpty)
        'originAirportIata': originAirportIata,
      if (transfer != null) 'transfer': transfer,
    };
    final data = await _request(
      'PATCH',
      '/admin/bookings/$bookingNumber/manual',
      body: payload,
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> cancelManualBooking(
    String bookingNumber, {
    String? reason,
    String? memo,
  }) async {
    final body = <String, dynamic>{};
    if (reason != null && reason.isNotEmpty) body['reason'] = reason;
    if (memo != null && memo.isNotEmpty) body['memo'] = memo;
    final data = await _request(
      'POST',
      '/admin/bookings/$bookingNumber/manual/cancel',
      body: body,
    );
    return Map<String, dynamic>.from(data as Map);
  }
}

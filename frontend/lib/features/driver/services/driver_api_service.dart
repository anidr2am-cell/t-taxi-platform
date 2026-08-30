import '../../../config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../models/driver_booking.dart';
import '../models/driver_status.dart';
import '../models/driver_vehicle.dart';
import 'driver_session.dart';
import 'driver_token_storage.dart';

class DriverApiException implements Exception {
  const DriverApiException(
    this.message, {
    this.errorCode,
    this.statusCode,
    this.details,
  });

  final String message;
  final String? errorCode;
  final int? statusCode;
  final Map<String, dynamic>? details;

  @override
  String toString() => message;

  String? get reasonCode {
    final fromDetails = details?['reasonCode']?.toString();
    if (fromDetails != null && fromDetails.trim().isNotEmpty) {
      return fromDetails.trim().toUpperCase();
    }
    return null;
  }

  bool get isAssignmentEnded =>
      errorCode == 'DRIVER_ASSIGNMENT_RELEASED' ||
      reasonCode == 'CUSTOMER_CANCELLED' ||
      reasonCode == 'ADMIN_CANCELLED' ||
      reasonCode == 'DRIVER_RELEASED' ||
      reasonCode == 'REASSIGNED_TO_ANOTHER_DRIVER';

  bool get isStaleStatus =>
      errorCode == 'INVALID_STATUS_TRANSITION' ||
      errorCode == 'BOOKING_NOT_FOUND' ||
      errorCode == 'DRIVER_ASSIGNMENT_RELEASED' ||
      message.toLowerCase().contains('invalid status');
}

class DriverApiService {
  DriverApiService({DriverSession? session})
    : _session = session ?? DriverSession();

  final DriverSession _session;

  DriverSession get session => _session;
  ApiClient get apiClient => _session.apiClient;
  DriverTokenStorage get tokenStorage => _session.tokenStorage;

  Future<String?> getSavedToken() => _session.tokenStorage.readAccessToken();

  Future<void> logout() => _session.expireSession();

  Future<String?> getDriverDisplayName() =>
      _session.tokenStorage.readDisplayName();

  Future<void> login({required String email, required String password}) async {
    final loginId = email.trim();
    final isPhone = !loginId.contains('@');
    final decoded = await _session.apiClient.postJson(
      '/auth/login',
      body: {
        if (isPhone) 'phone': loginId else 'email': loginId,
        'password': password,
      },
    );

    final data = Map<String, dynamic>.from(decoded['data'] as Map);
    final user = Map<String, dynamic>.from(data['user'] as Map);
    if (user['role'] != 'DRIVER') {
      throw const DriverApiException('Driver account required');
    }

    final displayName =
        user['name'] as String? ??
        user['phone'] as String? ??
        user['email'] as String? ??
        '';
    final refreshToken = data['refreshToken'] as String?;
    final expiresIn = data['expiresIn'];
    await _session.tokenStorage.saveLoginSession(
      accessToken: data['accessToken'] as String,
      refreshToken: refreshToken,
      expiresIn: expiresIn is num ? expiresIn.toInt() : null,
      displayName: displayName,
    );
  }

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

  Future<dynamic> _post(String path, {Map<String, dynamic>? body}) async {
    final token = await _requireAccessToken();
    try {
      final decoded = await _session.apiClient.postJson(
        path,
        bearerToken: token,
        body: body ?? {},
      );
      return decoded['data'];
    } on ApiException catch (err) {
      throw await _mapApiException(err);
    }
  }

  Future<dynamic> _patch(String path, {Map<String, dynamic>? body}) async {
    final token = await _requireAccessToken();
    try {
      final decoded = await _session.apiClient.patchJson(
        path,
        bearerToken: token,
        body: body ?? {},
      );
      return decoded['data'];
    } on ApiException catch (err) {
      throw await _mapApiException(err);
    }
  }

  Future<dynamic> _postFile(
    String path,
    List<int> bytes,
    String filename,
  ) async {
    final token = await _requireAccessToken();
    final ext = filename.contains('.')
        ? filename.split('.').last.toLowerCase()
        : '';
    final mimeType = switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
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
    final token = await getSavedToken();
    if (token == null || token.isEmpty) {
      throw const DriverApiException('Please log in again');
    }
    return token;
  }

  Future<DriverApiException> _mapApiException(ApiException err) async {
    if (err.kind == ApiFailureKind.unauthorized) {
      await logout();
    }
    return DriverApiException(
      err.message ?? 'Request failed',
      errorCode: err.errorCode,
      statusCode: err.statusCode,
      details: err.details,
    );
  }

  Future<Map<String, dynamic>> getRatingSummary() async {
    final data = await _get('/driver/rating-summary');
    return Map<String, dynamic>.from(data as Map);
  }

  Future<DriverStatus> getStatus() async {
    final data = await _get('/driver/status');
    return DriverStatus.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<DriverStatus> goOnline() async {
    final data = await _post('/driver/online');
    return DriverStatus.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<DriverStatus> goOffline() async {
    final data = await _post('/driver/offline');
    return DriverStatus.fromJson(Map<String, dynamic>.from(data as Map));
  }

  String resolveProfileAssetUrl(String? path) {
    if (path == null || path.trim().isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '${AppConfig.apiBaseUrl}$path';
  }

  Future<DriverJobsToday> getScheduledBookings() async {
    final data = await _get('/driver/bookings/scheduled');
    return DriverJobsToday.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<DriverJobsToday> getTodayBookings() async {
    return getScheduledBookings();
  }

  Future<DriverOpenCalls> getOpenCalls() async {
    final data = await _get('/driver/calls/open');
    return DriverOpenCalls.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<DriverBooking> claimOpenCall(
    String bookingNumber, {
    int? driverVehicleId,
  }) async {
    final data = await _post(
      '/driver/calls/$bookingNumber/claim',
      body: {
        if (driverVehicleId != null) 'driverVehicleId': driverVehicleId,
      },
    );
    final map = Map<String, dynamic>.from(data as Map);
    return DriverBooking.fromJson(
      Map<String, dynamic>.from(map['booking'] as Map? ?? map),
    );
  }

  Future<Map<String, dynamic>> lockUrgentCall(String bookingNumber) async {
    final data = await _post('/driver/urgent-calls/$bookingNumber/lock');
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> submitUrgentCallEta(
    String bookingNumber,
    int etaMinutes,
  ) async {
    final data = await _post(
      '/driver/urgent-calls/$bookingNumber/eta',
      body: {'etaMinutes': etaMinutes},
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> releaseAssignment(
    String bookingNumber, {
    required String reasonCode,
    String? reasonDetail,
  }) async {
    final data = await _post(
      '/driver/bookings/$bookingNumber/release',
      body: {
        'reasonCode': reasonCode,
        if (reasonDetail != null && reasonDetail.trim().isNotEmpty)
          'reasonDetail': reasonDetail.trim(),
      },
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> acceptBooking(String bookingNumber) async {
    final data = await _post('/driver/bookings/$bookingNumber/accept');
    return Map<String, dynamic>.from(data as Map);
  }

  Future<DriverBooking> confirmStandby(String bookingNumber) async {
    await acceptBooking(bookingNumber);
    return getBookingDetail(bookingNumber);
  }

  Future<DriverBooking> getBookingDetail(String bookingNumber) async {
    final data = await _get('/driver/bookings/$bookingNumber');
    return DriverBooking.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<DriverBooking> startOnRoute(String bookingNumber) async {
    final data = await _post('/driver/bookings/$bookingNumber/start-route');
    return DriverBooking.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<DriverBooking> markArrived(String bookingNumber) async {
    final data = await _post('/driver/bookings/$bookingNumber/arrive');
    return DriverBooking.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<DriverBooking> markPickedUp(String bookingNumber) async {
    final data = await _post('/driver/bookings/$bookingNumber/mark-picked-up');
    return DriverBooking.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<DriverBooking> endTrip(String bookingNumber) async {
    final data = await _post('/driver/bookings/$bookingNumber/end-trip');
    return DriverBooking.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<DriverBooking> completeTrip(String bookingNumber) async {
    return endTrip(bookingNumber);
  }

  Future<DriverBooking> scanBoarding(String bookingNumber, String token) async {
    final data = await _post(
      '/driver/bookings/$bookingNumber/scan-boarding',
      body: {'token': token},
    );
    return DriverBooking.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<DriverBooking> scanDropoff(String bookingNumber, String token) async {
    final data = await _post(
      '/driver/bookings/$bookingNumber/scan-dropoff',
      body: {'token': token},
    );
    return DriverBooking.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<Map<String, dynamic>> listNotifications({bool? unreadOnly}) async {
    final query = unreadOnly == true ? '?unreadOnly=true' : '';
    final data = await _get('/driver/notifications$query');
    return Map<String, dynamic>.from(data as Map);
  }

  Future<int> getUnreadNotificationCount() async {
    final data = await _get('/driver/notifications/unread-count');
    return Map<String, dynamic>.from(data as Map)['unreadCount'] as int? ?? 0;
  }

  Future<void> markNotificationRead(int notificationId) async {
    await _post('/driver/notifications/$notificationId/read');
  }

  Future<void> markAllNotificationsRead() async {
    await _post('/driver/notifications/read-all');
  }

  Future<Map<String, dynamic>> getProfile() async {
    final data = await _get('/driver/profile');
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> body) async {
    final data = await _patch('/driver/profile', body: body);
    final profile = Map<String, dynamic>.from(data as Map);
    final name = profile['name'] as String?;
    if (name != null && name.trim().isNotEmpty) {
      await _session.tokenStorage.saveDisplayName(name.trim());
    }
    return profile;
  }

  Future<Map<String, dynamic>> uploadProfileAvatar(
    List<int> bytes,
    String filename,
  ) async {
    final data = await _postFile('/driver/profile/avatar', bytes, filename);
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> uploadVehiclePhoto(
    List<int> bytes,
    String filename,
  ) async {
    final data = await _postFile(
      '/driver/profile/vehicle-photo',
      bytes,
      filename,
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<List<DriverVehicleItem>> listVehicles() async {
    final data = await _get('/driver/vehicles');
    final map = Map<String, dynamic>.from(data as Map);
    final items = map['items'] as List? ?? const [];
    return items
        .map(
          (item) => DriverVehicleItem.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  Future<DriverVehicleItem> createVehicle({
    required int vehicleTypeId,
    required String plateNumber,
    String? modelName,
    String? color,
    required List<({String field, String filename, List<int> bytes})> files,
  }) async {
    final token = await _requireAccessToken();
    final multipartFiles = <ApiMultipartFile>[];
    for (final file in files) {
      final ext = file.filename.contains('.')
          ? file.filename.split('.').last.toLowerCase()
          : '';
      final mimeType = switch (ext) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        'pdf' => 'application/pdf',
        _ => 'application/octet-stream',
      };
      multipartFiles.add(
        ApiMultipartFile(
          field: file.field,
          filename: file.filename,
          bytes: file.bytes,
          contentType: mimeType,
        ),
      );
    }
    try {
      final decoded = await _session.apiClient.postMultipart(
        '/driver/vehicles',
        bearerToken: token,
        timeout: const Duration(seconds: 60),
        fields: {
          'vehicleTypeId': '$vehicleTypeId',
          'plateNumber': plateNumber.trim(),
          if (modelName != null && modelName.trim().isNotEmpty)
            'modelName': modelName.trim(),
          if (color != null && color.trim().isNotEmpty) 'color': color.trim(),
        },
        files: multipartFiles,
      );
      return DriverVehicleItem.fromJson(
        Map<String, dynamic>.from((decoded['data'] as Map)),
      );
    } on ApiException catch (err) {
      throw await _mapApiException(err);
    }
  }
}

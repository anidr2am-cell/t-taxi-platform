import 'dart:async';

import 'package:tride_driver/core/network/api_exception.dart';
import 'package:tride_driver/core/storage/secure_token_storage.dart';
import 'package:tride_driver/features/auth/data/auth_api.dart';
import 'package:tride_driver/features/auth/data/auth_models.dart';
import 'package:tride_driver/features/bookings/data/booking_models.dart';
import 'package:tride_driver/features/bookings/data/booking_repository.dart';

DriverUser driverUser({int id = 7, String? name = 'Somchai'}) =>
    DriverUser(id: id, role: 'DRIVER', isActive: true, name: name);

AuthSession driverSession() => AuthSession(
  user: driverUser(),
  accessToken: 'test-access-token',
  refreshToken: 'test-refresh-token',
  expiresIn: 3600,
);

class FakeTokenStorage implements TokenStorage {
  FakeTokenStorage([this.tokens]);

  AuthTokens? tokens;
  int readCount = 0;
  int writeCount = 0;
  int clearCount = 0;

  @override
  Future<void> clear() async {
    clearCount++;
    tokens = null;
  }

  @override
  Future<AuthTokens?> read() async {
    readCount++;
    return tokens;
  }

  @override
  Future<void> write(AuthTokens value) async {
    writeCount++;
    tokens = value;
  }
}

class FakeAuthApi implements AuthDataSource {
  AuthSession loginResult = driverSession();
  DriverUser meResult = driverUser();
  ApiException? loginError;
  ApiException? meError;
  ApiException? logoutError;
  Completer<AuthSession>? loginCompleter;
  int loginCount = 0;
  int meCount = 0;
  int logoutCount = 0;

  @override
  Future<DriverUser> getMe(String accessToken) async {
    meCount++;
    if (meError case final error?) throw error;
    return meResult;
  }

  @override
  Future<AuthSession> login(String loginId, String password) async {
    loginCount++;
    if (loginCompleter case final completer?) return completer.future;
    if (loginError case final error?) throw error;
    return loginResult;
  }

  @override
  Future<void> logout(AuthTokens tokens) async {
    logoutCount++;
    if (logoutError case final error?) throw error;
  }
}

Map<String, dynamic> bookingJson({
  String bookingNumber = 'TX209912319999',
  String status = 'DRIVER_ASSIGNED',
  Object? assignmentStatus = 'ASSIGNED',
  String pickupDate = '2026-07-18',
  String pickupTime = '09:30',
  bool includeAssignmentStatus = true,
}) {
  final json = <String, dynamic>{
    'bookingNumber': bookingNumber,
    'status': status,
    'serviceType': {'code': 'AIRPORT_PICKUP', 'name': '공항 픽업'},
    'pickupDate': pickupDate,
    'pickupTime': pickupTime,
    'origin': 'Suvarnabhumi Airport',
    'destination': 'Test Hotel',
    'passengerCount': 2,
    'vehicleType': {'code': 'SEDAN', 'name': '세단'},
    'customerDisplayName': '테스트 고객',
    'flightNumber': 'TG100',
    'driverExpectedIncomeAmount': '900.00',
    'driverExpectedIncomeCurrency': 'THB',
  };
  if (includeAssignmentStatus) {
    json['assignmentStatus'] = assignmentStatus;
  }
  return json;
}

BookingSummary bookingSummary({
  String bookingNumber = 'TX209912319999',
  String status = 'DRIVER_ASSIGNED',
  Object? assignmentStatus = 'ASSIGNED',
  bool includeAssignmentStatus = true,
}) => BookingSummary.fromJson(
  bookingJson(
    bookingNumber: bookingNumber,
    status: status,
    assignmentStatus: assignmentStatus,
    includeAssignmentStatus: includeAssignmentStatus,
  ),
);

BookingList bookingList({List<BookingSummary>? items}) =>
    BookingList(serviceDate: '2026-07-18', items: items ?? [bookingSummary()]);

BookingDetail bookingDetail({
  String status = 'DRIVER_ASSIGNED',
  Object? assignmentStatus = 'ASSIGNED',
  bool includeAssignmentStatus = true,
  String bookingNumber = 'TX209912319999',
}) => BookingDetail.fromEnvelope({
  'success': true,
  'data': {
    ...bookingJson(
      bookingNumber: bookingNumber,
      status: status,
      assignmentStatus: assignmentStatus,
      includeAssignmentStatus: includeAssignmentStatus,
    ),
    'passengers': {'adults': 2, 'children': 0, 'infants': 0},
    'luggage': {
      'carriers20Inch': 1,
      'carriers24InchPlus': 1,
      'golfBags': 0,
      'specialItems': null,
    },
    'flight': {
      'flightNumber': 'TG100',
      'flightStatus': 'ON_TIME',
      'latestEstimatedArrival': '2026-07-18 08:30:00',
      'delayMinutes': 0,
    },
    'specialInstructions': 'Synthetic fixture note',
    'customerPaymentAmount': 1200,
    'customerPaymentCurrency': 'THB',
    'companyCommissionAmount': 300,
    'companyCommissionCurrency': 'THB',
  },
});

Map<String, dynamic> acceptanceEnvelope({
  String bookingNumber = 'TX209912319999',
  String bookingStatus = 'DRIVER_ASSIGNED',
  String assignmentStatus = 'ACCEPTED',
  String? acceptedAt = '2026-07-18T02:30:00.000Z',
  bool idempotent = false,
}) => {
  'success': true,
  'message': 'Booking accepted',
  'data': {
    'bookingNumber': bookingNumber,
    'bookingStatus': bookingStatus,
    'assignmentStatus': assignmentStatus,
    'acceptedAt': acceptedAt,
    'idempotent': idempotent,
    'ignoredExtra': 'ok',
  },
};

class FakeBookingReader implements BookingReader {
  BookingList listResult = bookingList();
  BookingDetail detailResult = bookingDetail();
  BookingAcceptance acceptResult = BookingAcceptance.fromEnvelope(
    acceptanceEnvelope(),
  );
  Object? listError;
  Object? detailError;
  Object? acceptError;
  Completer<BookingList>? listCompleter;
  Completer<BookingDetail>? detailCompleter;
  Completer<BookingAcceptance>? acceptCompleter;
  int listCount = 0;
  int detailCount = 0;
  int acceptCount = 0;
  String? requestedBookingNumber;
  String? acceptedBookingNumber;
  List<BookingDetail> detailQueue = [];

  @override
  Future<BookingDetail> getBookingDetail(String bookingNumber) async {
    detailCount++;
    requestedBookingNumber = bookingNumber;
    if (detailCompleter case final completer?) return completer.future;
    if (detailQueue.isNotEmpty) {
      return detailQueue.removeAt(0);
    }
    if (detailError case final error?) throw error;
    return detailResult;
  }

  @override
  Future<BookingList> getTodayBookings() async {
    listCount++;
    if (listCompleter case final completer?) return completer.future;
    if (listError case final error?) throw error;
    return listResult;
  }

  @override
  Future<BookingAcceptance> acceptBooking(String bookingNumber) async {
    acceptCount++;
    acceptedBookingNumber = bookingNumber;
    if (acceptCompleter case final completer?) return completer.future;
    if (acceptError case final error?) throw error;
    return acceptResult;
  }
}

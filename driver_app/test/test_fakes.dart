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
  String bookingNumber = 'TX202607180001',
  String status = 'DRIVER_ASSIGNED',
  String pickupDate = '2026-07-18',
  String pickupTime = '09:30',
}) => {
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

BookingSummary bookingSummary({
  String bookingNumber = 'TX202607180001',
  String status = 'DRIVER_ASSIGNED',
}) => BookingSummary.fromJson(
  bookingJson(bookingNumber: bookingNumber, status: status),
);

BookingList bookingList({List<BookingSummary>? items}) =>
    BookingList(serviceDate: '2026-07-18', items: items ?? [bookingSummary()]);

BookingDetail bookingDetail({String status = 'DRIVER_ASSIGNED'}) =>
    BookingDetail.fromEnvelope({
      'success': true,
      'data': {
        ...bookingJson(status: status),
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

class FakeBookingReader implements BookingReader {
  BookingList listResult = bookingList();
  BookingDetail detailResult = bookingDetail();
  Object? listError;
  Object? detailError;
  Completer<BookingList>? listCompleter;
  Completer<BookingDetail>? detailCompleter;
  int listCount = 0;
  int detailCount = 0;
  String? requestedBookingNumber;

  @override
  Future<BookingDetail> getBookingDetail(String bookingNumber) async {
    detailCount++;
    requestedBookingNumber = bookingNumber;
    if (detailCompleter case final completer?) return completer.future;
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
}

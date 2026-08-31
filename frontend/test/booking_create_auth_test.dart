import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/controllers/auth_controller.dart';
import 'package:frontend/features/auth/models/social_login_return_context.dart';
import 'package:frontend/features/auth/services/auth_api_service.dart';
import 'package:frontend/features/auth/services/auth_token_storage.dart';
import 'package:frontend/features/auth/services/customer_session.dart';
import 'package:frontend/features/booking/models/booking_create_result.dart';
import 'package:frontend/features/booking/models/pricing_result.dart';
import 'package:frontend/features/booking/models/urgent_negotiation_status.dart';
import 'package:frontend/features/booking/models/vehicle_recommendation.dart';
import 'package:frontend/features/booking/services/booking_api_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/booking_wizard_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('createBooking sends Authorization header when accessToken is provided', () async {
    String? authorizationHeader;
    final api = BookingApiService.test(
      baseUrl: 'http://localhost:3000',
      client: MockClient((request) async {
        authorizationHeader = request.headers['authorization'];
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'bookingNumber': 'TX202607010001',
              'status': 'PENDING',
              'paymentMethod': 'PAY_DRIVER',
              'paymentStatus': 'UNPAID',
              'totalAmount': 1500,
              'currency': 'THB',
            },
          }),
          201,
        );
      }),
    );

    await api.createBooking(
      {'scheduledPickupAt': '2026-07-01T09:30:00+07:00'},
      accessToken: 'member-jwt',
    );

    expect(authorizationHeader, 'Bearer member-jwt');
  });

  test('createBooking omits Authorization header for guest flow', () async {
    String? authorizationHeader;
    final api = BookingApiService.test(
      baseUrl: 'http://localhost:3000',
      client: MockClient((request) async {
        authorizationHeader = request.headers['authorization'];
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'bookingNumber': 'TX202607010001',
              'status': 'PENDING',
              'paymentMethod': 'PAY_DRIVER',
              'paymentStatus': 'UNPAID',
              'totalAmount': 1500,
              'currency': 'THB',
              'guestAccessToken': 'guest-token',
            },
          }),
          201,
        );
      }),
    );

    final guestResult = await api.createBooking(
      {'scheduledPickupAt': '2026-07-01T09:30:00+07:00'},
    );

    expect(authorizationHeader, isNull);
    expect(guestResult.guestAccessToken, 'guest-token');
  });

  test('createBooking treats blank accessToken as guest flow', () async {
    String? authorizationHeader;
    final api = BookingApiService.test(
      baseUrl: 'http://localhost:3000',
      client: MockClient((request) async {
        authorizationHeader = request.headers['authorization'];
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'bookingNumber': 'TX202607010001',
              'status': 'PENDING',
              'paymentMethod': 'PAY_DRIVER',
              'paymentStatus': 'UNPAID',
              'totalAmount': 1500,
              'currency': 'THB',
              'guestAccessToken': 'guest-token',
            },
          }),
          201,
        );
      }),
    );

    await api.createBooking(
      {'scheduledPickupAt': '2026-07-01T09:30:00+07:00'},
      accessToken: '   ',
    );

    expect(authorizationHeader, isNull);
  });

  test('createBooking member response has null guestAccessToken', () async {
    final api = BookingApiService.test(
      baseUrl: 'http://localhost:3000',
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'bookingNumber': 'TX202607010001',
              'status': 'PENDING',
              'paymentMethod': 'PAY_DRIVER',
              'paymentStatus': 'UNPAID',
              'totalAmount': 1500,
              'currency': 'THB',
              'guestAccessToken': null,
            },
          }),
          201,
        );
      }),
    );

    final memberResult = await api.createBooking(
      {'scheduledPickupAt': '2026-07-01T09:30:00+07:00'},
      accessToken: 'member-jwt',
    );

    expect(memberResult.guestAccessToken, isNull);
  });

  test('submitBooking forwards accessToken to createBooking', () async {
    final api = MemberCreateTrackingApi();
    final controller = await buildContractAirportPickupController(api: api);

    final result = await controller.submitBooking(accessToken: 'member-jwt');

    expect(result, isNotNull);
    expect(api.lastAccessToken, 'member-jwt');
    expect(result!.guestAccessToken, isNull);
  });

  test('submitBooking without accessToken keeps guest token in response', () async {
    final api = MemberCreateTrackingApi();
    final controller = await buildContractAirportPickupController(api: api);

    final result = await controller.submitBooking();

    expect(result, isNotNull);
    expect(api.lastAccessToken, isNull);
    expect(result!.guestAccessToken, 'guest-token');
  });

  test('claim API is skipped when booking result has no guestAccessToken', () async {
    final claimCalls = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/social/kakao')) {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'accessToken': 'kakao-access-token',
              'refreshToken': 'refresh-token',
              'expiresIn': 3600,
              'user': {
                'id': 42,
                'email': 'guest@example.com',
                'role': 'CUSTOMER',
                'name': 'Minji',
                'phone': null,
                'locale': 'ko',
                'isActive': true,
              },
            },
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/customer/bookings/claim')) {
        claimCalls.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(jsonEncode({'success': true, 'data': {}}), 200);
      }
      return http.Response('{}', 500);
    });
    final tokenStorage = AuthTokenStorage();
    final customerSession = CustomerSession(
      tokenStorage: tokenStorage,
      httpClient: client,
      baseUrl: 'http://localhost:3000',
    );
    final authController = AuthController(
      apiService: AuthApiService(
        client: client,
        baseUrl: 'http://localhost:3000',
        customerSession: customerSession,
      ),
      tokenStorage: tokenStorage,
      customerSession: customerSession,
    );
    await authController.initialize();

    await authController.completeSignInWithKakaoCodeForTest(
      code: 'mock-kakao-code',
      redirectUri: 'https://trider.taxi/auth/kakao/callback',
      claimContext: SocialLoginReturnContext.fromBookingComplete(
        result: BookingCreateResult(
          bookingNumber: 'TX202607010001',
          status: 'PENDING',
          paymentMethod: 'PAY_DRIVER',
          paymentStatus: 'UNPAID',
          totalAmount: 1500,
          currency: 'THB',
          guestAccessToken: null,
          boardingQrToken: 'boarding-token',
          trustMessage: 'Booking received',
        ),
        serviceLabel: 'Airport Pickup',
        baseUri: Uri.parse('https://trider.taxi/booking'),
      ),
    );

    expect(claimCalls, isEmpty);
    expect(authController.isLoggedIn, isTrue);
  });
}

class MemberCreateTrackingApi implements BookingApiService {
  String? lastAccessToken;
  final CapturingBookingApi _delegate = CapturingBookingApi();

  @override
  Future<BookingCreateResult> createBooking(
    Map<String, dynamic> body, {
    String? idempotencyKey,
    String? accessToken,
  }) async {
    lastAccessToken = accessToken;
    final isMember = accessToken != null && accessToken.trim().isNotEmpty;
    return BookingCreateResult(
      bookingId: 1,
      bookingNumber: 'TX202607130001',
      status: 'OPEN',
      paymentMethod: 'PAY_DRIVER',
      paymentStatus: 'UNPAID',
      totalAmount: 1300,
      currency: 'THB',
      guestAccessToken: isMember ? null : 'guest-token',
      boardingQrToken: 'boarding-token',
      trustMessage: 'trust',
      isUrgentRequest: false,
      canCancel: true,
    );
  }

  @override
  Future<PricingResult> calculatePricing({
    required String serviceTypeCode,
    required String vehicleTypeCode,
    int vehicleCount = 1,
    String? originAirportIata,
    String? destinationRegion,
    String? originLocationCode,
    String? destinationLocationCode,
    bool nameSign = false,
    String? scheduledPickupAt,
    int adults = 1,
    int children = 0,
    int infants = 0,
    int luggage20 = 0,
    int luggage24 = 0,
    int golfBags = 0,
    int specialLuggageCount = 0,
    double? originLat,
    double? originLng,
    double? destinationLat,
    double? destinationLng,
  }) {
    return _delegate.calculatePricing(
      serviceTypeCode: serviceTypeCode,
      vehicleTypeCode: vehicleTypeCode,
      vehicleCount: vehicleCount,
      originAirportIata: originAirportIata,
      destinationRegion: destinationRegion,
      originLocationCode: originLocationCode,
      destinationLocationCode: destinationLocationCode,
      nameSign: nameSign,
      scheduledPickupAt: scheduledPickupAt,
      adults: adults,
      children: children,
      infants: infants,
      luggage20: luggage20,
      luggage24: luggage24,
      golfBags: golfBags,
      specialLuggageCount: specialLuggageCount,
      originLat: originLat,
      originLng: originLng,
      destinationLat: destinationLat,
      destinationLng: destinationLng,
    );
  }

  @override
  Future<VehicleRecommendation> recommendVehicle({
    required int adults,
    int children = 0,
    int infants = 0,
    int luggage20 = 0,
    int luggage24 = 0,
    int golfBags = 0,
    int specialLuggageCount = 0,
  }) {
    return _delegate.recommendVehicle(
      adults: adults,
      children: children,
      infants: infants,
      luggage20: luggage20,
      luggage24: luggage24,
      golfBags: golfBags,
      specialLuggageCount: specialLuggageCount,
    );
  }

  @override
  Future<DropoffQrIssueResult> issueDropoffQr({
    required String bookingNumber,
    required String? guestAccessToken,
  }) {
    return _delegate.issueDropoffQr(
      bookingNumber: bookingNumber,
      guestAccessToken: guestAccessToken,
    );
  }

  @override
  Future<BoardingQrIssueResult> issueBoardingQr({
    required String bookingNumber,
    required String? guestAccessToken,
    bool forceReissue = false,
  }) {
    return _delegate.issueBoardingQr(
      bookingNumber: bookingNumber,
      guestAccessToken: guestAccessToken,
      forceReissue: forceReissue,
    );
  }

  @override
  Future<UrgentNegotiationStatus> getUrgentNegotiation({
    required String bookingNumber,
    String? guestAccessToken,
  }) {
    return _delegate.getUrgentNegotiation(
      bookingNumber: bookingNumber,
      guestAccessToken: guestAccessToken,
    );
  }

  @override
  Future<UrgentDecisionResult> submitUrgentDecision({
    required String bookingNumber,
    required String decision,
    String? guestAccessToken,
  }) {
    return _delegate.submitUrgentDecision(
      bookingNumber: bookingNumber,
      decision: decision,
      guestAccessToken: guestAccessToken,
    );
  }
}

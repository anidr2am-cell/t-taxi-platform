import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/account/pages/account_page.dart';
import 'package:frontend/features/account/pages/mileage_history_page.dart';
import 'package:frontend/features/account/services/mileage_api_service.dart';
import 'package:frontend/features/auth/controllers/auth_controller.dart';
import 'package:frontend/features/auth/services/auth_api_service.dart';
import 'package:frontend/features/auth/services/auth_token_storage.dart';
import 'package:frontend/features/auth/services/google_sign_in_service.dart';
import 'package:frontend/features/auth/widgets/booking_social_login_section.dart';
import 'package:frontend/features/booking/models/guest_booking_lookup_result.dart';
import 'package:frontend/features/booking/pages/my_bookings_page.dart';
import 'package:frontend/features/booking/services/customer_bookings_api_service.dart';
import 'package:frontend/features/support/pages/customer_support_page.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeMileageApiService extends MileageApiService {
  _FakeMileageApiService(this.result, {this.error});

  final MileageBalanceResult? result;
  final Object? error;

  @override
  Future<MileageBalanceResult> getMileageBalance() async {
    if (error != null) {
      throw error!;
    }
    return result!;
  }
}

class _FakeCustomerBookingsApiService extends CustomerBookingsApiService {
  _FakeCustomerBookingsApiService({
    this.counts = const CustomerBookingStatusCounts(
      waiting: 1,
      assigned: 2,
      inProgress: 0,
      settlementPending: 1,
      completed: 3,
      reviewPending: 1,
    ),
    this.recentBookings = const [],
    this.countsError,
    this.recentError,
  });

  final CustomerBookingStatusCounts counts;
  final List<GuestBookingLookupResult> recentBookings;
  final Object? countsError;
  final Object? recentError;

  @override
  Future<CustomerBookingStatusCounts> getStatusCounts() async {
    if (countsError != null) throw countsError!;
    return counts;
  }

  @override
  Future<CustomerBookingsPageResult> listMyBookings({
    int page = 1,
    int limit = 20,
  }) async {
    if (recentError != null) throw recentError!;
    return CustomerBookingsPageResult(
      bookings: recentBookings,
      total: recentBookings.length,
      page: page,
      limit: limit,
    );
  }
}

Future<AuthController> _prepareLoggedInController() async {
  SharedPreferences.setMockInitialValues({
    AuthTokenStorage.accessTokenKey: 'saved-access',
    AuthTokenStorage.refreshTokenKey: 'saved-refresh',
    AuthTokenStorage.userJsonKey: jsonEncode({
      'id': 7,
      'email': 'saved@example.com',
      'role': 'CUSTOMER',
      'name': 'Saved User',
      'phone': null,
      'locale': 'ko',
      'isActive': true,
      'authProvider': 'KAKAO',
      'linkedProviders': ['KAKAO'],
    }),
  });

  final controller = AuthController(
    apiService: AuthApiService(
      client: MockClient((_) async => http.Response('{}', 500)),
      baseUrl: 'http://localhost:3000',
    ),
    tokenStorage: AuthTokenStorage(),
    googleSignInService: GoogleSignInService()..markInitializedForTest(),
  );
  await controller.initialize();
  return controller;
}

Widget _wrapAccountPage({
  required AuthController authController,
  MileageApiService? mileageApiService,
  CustomerBookingsApiService? customerBookingsApiService,
}) {
  return MaterialApp(
    locale: const Locale('ko'),
    supportedLocales: const [Locale('ko')],
    localizationsDelegates: [
      AppLocalizationsDelegate('ko'),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    routes: {
      '/my-bookings': (_) => const MyBookingsPage(),
      '/support': (_) => const CustomerSupportPage(),
    },
    home: AuthScope(
      controller: authController,
      child: AccountPage(
        mileageApiService: mileageApiService,
        customerBookingsApiService: customerBookingsApiService,
      ),
    ),
  );
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.tap(finder);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.window.physicalSizeTestValue = const Size(800, 1200);
    binding.window.devicePixelRatioTestValue = 1.0;
    addTearDown(binding.window.clearPhysicalSizeTestValue);
    addTearDown(binding.window.clearDevicePixelRatioTestValue);
  });

  testWidgets('account page renders profile, mileage balance, and menus', (
    tester,
  ) async {
    final authController = await _prepareLoggedInController();

    await tester.pumpWidget(
      _wrapAccountPage(
        authController: authController,
        mileageApiService: _FakeMileageApiService(
          const MileageBalanceResult(balance: 1250),
        ),
        customerBookingsApiService: _FakeCustomerBookingsApiService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('account_page')), findsOneWidget);
    expect(find.text('Saved User'), findsOneWidget);
    expect(find.text('saved@example.com'), findsOneWidget);
    expect(find.byKey(const Key('account_auth_provider_badge')), findsOneWidget);
    expect(find.text('카카오로 로그인'), findsOneWidget);
    expect(find.byKey(const Key('account_mileage_balance')), findsOneWidget);
    expect(find.text('1,250P'), findsOneWidget);
    expect(find.byKey(const Key('account_booking_count_waiting')), findsOneWidget);
    expect(find.text('예약대기'), findsOneWidget);
    expect(find.byKey(const Key('account_coupon_menu')), findsOneWidget);
    expect(find.byKey(const Key('account_my_reviews_menu')), findsOneWidget);
    expect(find.byKey(const Key('account_customer_support_menu')), findsOneWidget);
    expect(find.byKey(const Key('account_logout_menu')), findsOneWidget);
  });

  testWidgets('account page shows mileage loading then error state', (
    tester,
  ) async {
    final authController = await _prepareLoggedInController();

    await tester.pumpWidget(
      _wrapAccountPage(
        authController: authController,
        mileageApiService: _FakeMileageApiService(
          null,
          error: const MileageApiException('failed'),
        ),
        customerBookingsApiService: _FakeCustomerBookingsApiService(),
      ),
    );

    await tester.pump();
    expect(find.byKey(const Key('account_mileage_loading')), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('account_mileage_error')), findsOneWidget);
    expect(find.text('failed'), findsOneWidget);
  });

  testWidgets('account booking count tap navigates to my bookings', (
    tester,
  ) async {
    final authController = await _prepareLoggedInController();

    await tester.pumpWidget(
      _wrapAccountPage(
        authController: authController,
        mileageApiService: _FakeMileageApiService(
          const MileageBalanceResult(balance: 0),
        ),
        customerBookingsApiService: _FakeCustomerBookingsApiService(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('account_booking_count_waiting')));
    await tester.pumpAndSettle();

    expect(find.byType(MyBookingsPage), findsOneWidget);
  });

  testWidgets('account mileage balance opens mileage history page', (
    tester,
  ) async {
    final authController = await _prepareLoggedInController();

    await tester.pumpWidget(
      _wrapAccountPage(
        authController: authController,
        mileageApiService: _FakeMileageApiService(
          const MileageBalanceResult(balance: 100),
        ),
        customerBookingsApiService: _FakeCustomerBookingsApiService(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('account_mileage_balance')));
    await tester.pumpAndSettle();

    expect(find.byType(MileageHistoryPage), findsOneWidget);
  });

  testWidgets('account customer support menu navigates to support page', (
    tester,
  ) async {
    final authController = await _prepareLoggedInController();

    await tester.pumpWidget(
      _wrapAccountPage(
        authController: authController,
        mileageApiService: _FakeMileageApiService(
          const MileageBalanceResult(balance: 0),
        ),
        customerBookingsApiService: _FakeCustomerBookingsApiService(),
      ),
    );
    await tester.pumpAndSettle();

    await _tapVisible(
      tester,
      find.byKey(const Key('account_customer_support_menu')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CustomerSupportPage), findsOneWidget);
  });

  testWidgets('account coupon menu shows coming soon snackbar', (
    tester,
  ) async {
    final authController = await _prepareLoggedInController();

    await tester.pumpWidget(
      _wrapAccountPage(
        authController: authController,
        mileageApiService: _FakeMileageApiService(
          const MileageBalanceResult(balance: 0),
        ),
        customerBookingsApiService: _FakeCustomerBookingsApiService(),
      ),
    );
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.byKey(const Key('account_coupon_menu')));
    await tester.pumpAndSettle();

    expect(find.text('준비 중입니다'), findsOneWidget);
  });

  testWidgets('account page logout signs out and shows snackbar', (
    tester,
  ) async {
    final authController = await _prepareLoggedInController();

    await tester.pumpWidget(
      _wrapAccountPage(
        authController: authController,
        mileageApiService: _FakeMileageApiService(
          const MileageBalanceResult(balance: 0),
        ),
        customerBookingsApiService: _FakeCustomerBookingsApiService(),
      ),
    );
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.byKey(const Key('account_logout_menu')));
    await tester.pumpAndSettle();

    final logoutButton = find.widgetWithText(FilledButton, '로그아웃');
    await _tapVisible(tester, logoutButton);
    await tester.pumpAndSettle();

    expect(authController.isLoggedIn, isFalse);
    expect(find.text('로그아웃되었습니다'), findsOneWidget);
  });
}

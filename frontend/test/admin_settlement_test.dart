import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/admin_settlement/pages/admin_settlement_queue_page.dart';
import 'package:frontend/features/admin_settlement/services/admin_settlement_api_service.dart';
import 'package:frontend/features/admin_settlement/utils/admin_settlement_test_data_filter.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAdminSettlementApiService extends AdminSettlementApiService {
  _FakeAdminSettlementApiService({this.listItems = const []});

  bool approved = false;
  final List<Map<String, dynamic>> listItems;

  @override
  Future<Map<String, dynamic>> listSettlements({
    String? status,
    bool overdueOnly = false,
    int page = 1,
    int limit = 20,
  }) async {
    return {'items': listItems};
  }

  @override
  Future<Map<String, dynamic>> getSettlement(String bookingNumber) async {
    return {
      'bookingNumber': bookingNumber,
      'commissionAmount': 200,
      'currency': 'THB',
      'commissionStatus': approved ? 'APPROVED' : 'RECEIPT_SUBMITTED',
      'receiptStatus': approved ? 'APPROVED' : 'RECEIPT_SUBMITTED',
      'canApprove': !approved,
      'canManualApprove': false,
      'receiptMetadata': {
        'filename': 'synthetic-receipt.png',
        'contentType': 'image/png',
      },
    };
  }

  @override
  Future<Map<String, dynamic>> approve(String bookingNumber) async {
    approved = true;
    return getSettlement(bookingNumber);
  }
}

Widget _wrap(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLanguages
        .map((code) => Locale(code))
        .toList(),
    localizationsDelegates: [
      AppLocalizationsDelegate('en'),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: child,
  );
}

void main() {
  test('admin settlement E2E route is disabled by default', () {
    expect(app.adminE2ERoutesEnabled(), isFalse);
    expect(
      app.buildAdminE2ERoute(
        const RouteSettings(
          name: '/admin/e2e/settlement-detail?bookingNumber=TX202607180199',
        ),
      ),
      isNull,
    );
  });

  test('admin settlement E2E route can be enabled by build flag', () {
    expect(app.adminE2ERoutesEnabled(enabled: true), isTrue);
    final route = app.buildAdminE2ERoute(
      const RouteSettings(
        name: '/admin/e2e/settlement-detail?bookingNumber=TX202607180199',
      ),
      enabled: true,
    );
    expect(route, isNotNull);
  });

  test('admin settlement E2E route requires a valid booking number', () {
    expect(
      app.adminE2ESettlementBookingNumber(
        Uri.parse('/admin/e2e/settlement-detail?bookingNumber=TX202607180199'),
      ),
      'TX202607180199',
    );
    expect(
      app.adminE2ESettlementBookingNumber(
        Uri.parse('/admin/e2e/settlement-detail?bookingNumber='),
      ),
      isNull,
    );
    expect(
      app.adminE2ESettlementBookingNumber(
        Uri.parse('/admin/e2e/settlement-detail?bookingNumber=../driver'),
      ),
      isNull,
    );
  });

  testWidgets('admin settlement E2E route blocks missing admin auth', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      _wrap(
        app.AdminE2ESettlementDetailRoute(
          uri: Uri.parse(
            '/admin/e2e/settlement-detail?bookingNumber=TX202607180199',
          ),
          routesEnabled: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AdminSettlementDetailPage), findsNothing);
    expect(find.text('Admin login required'), findsOneWidget);
  });

  testWidgets('admin settlement E2E route blocks empty booking number', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'admin_access_token': 'token'});
    await tester.pumpWidget(
      _wrap(
        app.AdminE2ESettlementDetailRoute(
          uri: Uri.parse('/admin/e2e/settlement-detail?bookingNumber='),
          routesEnabled: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AdminSettlementDetailPage), findsNothing);
    expect(
      find.text('Admin E2E settlement booking number is required'),
      findsOneWidget,
    );
  });

  testWidgets('admin settlement approval requires confirmation', (
    tester,
  ) async {
    final api = _FakeAdminSettlementApiService();
    var changed = 0;

    await tester.pumpWidget(
      _wrap(
        AdminSettlementDetailPage(
          bookingNumber: 'TX202607180199',
          api: api,
          onChanged: () => changed++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();

    expect(find.text('Approve settlement'), findsOneWidget);
    expect(api.approved, isFalse);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Approve settlement'), findsNothing);
    expect(api.approved, isFalse);
    expect(changed, 0);

    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Approve').last);
    await tester.pumpAndSettle();

    expect(api.approved, isTrue);
    expect(changed, 1);
    expect(find.text('Status: APPROVED'), findsOneWidget);
  });

  test('admin settlement test-data filter hides exactly 100 THB commission', () {
    const testItem = {
      'bookingNumber': 'TX-TEST-100',
      'commissionAmount': 100,
      'currency': 'THB',
    };
    const realItem = {
      'bookingNumber': 'TX-REAL-200',
      'commissionAmount': 200,
      'currency': 'THB',
    };
    const nearMissAmount = {
      'bookingNumber': 'TX-NEAR-101',
      'commissionAmount': 101,
      'currency': 'THB',
    };
    const nearMissCurrency = {
      'bookingNumber': 'TX-NEAR-USD',
      'commissionAmount': 100,
      'currency': 'USD',
    };

    expect(isAdminSettlementTestDataItem(testItem), isTrue);
    expect(isAdminSettlementTestDataItem(realItem), isFalse);
    expect(isAdminSettlementTestDataItem(nearMissAmount), isFalse);
    expect(isAdminSettlementTestDataItem(nearMissCurrency), isFalse);

    final filtered = filterAdminSettlementItems(
      [testItem, realItem, nearMissAmount, nearMissCurrency],
      includeTestData: false,
    );
    expect(filtered, [realItem, nearMissAmount, nearMissCurrency]);
  });

  testWidgets('admin settlement queue hides 100 THB test rows by default', (
    tester,
  ) async {
    final api = _FakeAdminSettlementApiService(
      listItems: [
        {
          'bookingNumber': 'TX-TEST-100',
          'driverName': 'Test Driver',
          'commissionAmount': 100,
          'currency': 'THB',
          'commissionStatus': 'PENDING',
        },
        {
          'bookingNumber': 'TX-REAL-200',
          'driverName': 'Real Driver',
          'commissionAmount': 200,
          'currency': 'THB',
          'commissionStatus': 'PENDING',
        },
      ],
    );

    await tester.pumpWidget(_wrap(AdminSettlementQueuePage(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('TX-TEST-100'), findsNothing);
    expect(find.text('TX-REAL-200'), findsOneWidget);

    await tester.tap(find.text('테스트 데이터 포함 보기'));
    await tester.pumpAndSettle();

    expect(find.text('TX-TEST-100'), findsOneWidget);
    expect(find.text('TX-REAL-200'), findsOneWidget);
  });
}

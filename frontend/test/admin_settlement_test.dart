import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/admin_settlement/pages/admin_settlement_queue_page.dart';
import 'package:frontend/features/admin_settlement/services/admin_settlement_api_service.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAdminSettlementApiService extends AdminSettlementApiService {
  _FakeAdminSettlementApiService();

  bool approved = false;

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
  });

  test('admin settlement E2E route can be enabled by build flag', () {
    expect(app.adminE2ERoutesEnabled(enabled: true), isTrue);
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
}

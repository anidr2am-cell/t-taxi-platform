import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/admin_settlement/pages/admin_settlement_queue_page.dart';
import 'package:frontend/features/admin_settlement/services/admin_settlement_api_service.dart';
import 'package:frontend/l10n/app_localizations.dart';

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

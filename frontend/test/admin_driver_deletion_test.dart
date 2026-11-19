import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/admin_dispatch/services/admin_dispatch_api_service.dart';
import 'package:frontend/features/admin_dispatch/widgets/admin_driver_detail_dialog.dart';
import 'package:frontend/l10n/app_localizations.dart';

class _Api extends AdminDispatchApiService {
  String? deletedReason;
  bool block = false;
  @override
  Future<Map<String, dynamic>> getDriverDetail(int id) async => {
    'displayName': 'QA Driver',
    'vehicles': [],
    'driverStatus': 'OFFLINE',
  };
  @override
  Future<void> deleteDriver(int id, String reason) async {
    if (block) {
      throw const AdminDispatchApiException(
        'Blocked',
        errorCode: 'DRIVER_DELETE_BLOCKED',
        errors: [
          AdminDispatchApiErrorDetail(
            field: 'bookingNumber',
            message: 'TX209901010001',
          ),
        ],
      );
    }
    deletedReason = reason;
  }
}

Widget host(_Api api) => MaterialApp(
  locale: const Locale('ko'),
  supportedLocales: const [Locale('ko')],
  localizationsDelegates: [
    AppLocalizationsDelegate('ko'),
    ...GlobalMaterialLocalizations.delegates,
  ],
  home: Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () => showDialog<bool>(
          context: context,
          builder: (_) => AdminDriverDetailDialog(driverId: 2, api: api),
        ),
        child: const Text('open'),
      ),
    ),
  ),
);

void main() {
  testWidgets('driver deletion requires a reason and explicit confirmation', (
    tester,
  ) async {
    final api = _Api();
    await tester.pumpWidget(host(api));
      await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('기사 삭제'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(api.deletedReason, isNull);
    await tester.enterText(find.byType(TextField), 'QA deletion');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(api.deletedReason, 'QA deletion');
    expect(find.byType(AdminDriverDetailDialog), findsNothing);
  });

  testWidgets(
    'blocked deletion shows affected bookings and keeps the driver detail open',
    (tester) async {
      final api = _Api()..block = true;
      await tester.pumpWidget(host(api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('기사 삭제'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'QA deletion');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(find.textContaining('TX209901010001'), findsOneWidget);
      expect(find.byType(AdminDriverDetailDialog), findsOneWidget);
      expect(api.deletedReason, isNull);
    },
  );
}


import 'package:tride_driver/features/dispatch/presentation/driver_admin_manual_call_notice.dart';
import 'package:tride_driver/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap({
    required bool isAdminManualCall,
    required bool requiresBankAccountConfirmation,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('ko'),
      home: Scaffold(
        body: DriverAdminManualCallNotice(
          isAdminManualCall: isAdminManualCall,
          requiresBankAccountConfirmation: requiresBankAccountConfirmation,
        ),
      ),
    );
  }

  testWidgets('normal call shows no admin manual notice', (tester) async {
    await tester.pumpWidget(
      wrap(
        isAdminManualCall: false,
        requiresBankAccountConfirmation: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('driverAdminManualCallNotice')), findsNothing);
  });

  testWidgets('admin manual driver collect shows badge only', (tester) async {
    await tester.pumpWidget(
      wrap(
        isAdminManualCall: true,
        requiresBankAccountConfirmation: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('관리자 등록 콜'), findsOneWidget);
    expect(find.text('커미션 없음'), findsOneWidget);
    expect(find.textContaining('회원가입시 등록된 계좌'), findsNothing);
  });

  testWidgets('admin manual admin collected shows badge and bank notice', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        isAdminManualCall: true,
        requiresBankAccountConfirmation: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('관리자 등록 콜'), findsOneWidget);
    expect(find.text('커미션 없음'), findsOneWidget);
    expect(find.textContaining('회원가입시 등록된 계좌'), findsOneWidget);
  });
}

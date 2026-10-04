import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/widgets/customer_payment_instructions_card.dart';
import 'package:frontend/l10n/app_localizations.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    locale: const Locale('ko'),
    supportedLocales: AppLocalizations.supportedLanguages
        .map((code) => Locale(code))
        .toList(),
    localizationsDelegates: [
      AppLocalizationsDelegate('ko'),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  testWidgets(
    'KRW bank transfer shows configured account and depositor notice',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          const CustomerPaymentInstructionsCard(
            paymentMethod: 'BANK_TRANSFER',
            paymentCurrency: 'KRW',
            instructions: {
              'bankName': '테스트은행',
              'accountName': 'TRider',
              'accountNumber': '123-456',
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('테스트은행'), findsOneWidget);
      expect(find.text('TRider'), findsOneWidget);
      expect(find.text('123-456'), findsOneWidget);
      expect(
        find.text('예약자명과 입금자의 이름이 다른 경우 관리자에게 입금자명을 보내주셔야 처리가 완료됩니다.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('card payment tells customer to contact an administrator', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const CustomerPaymentInstructionsCard(paymentMethod: 'CARD')),
    );
    await tester.pumpAndSettle();

    expect(find.text('카드결제의 경우 관리자를 통해 결제가 가능합니다.'), findsOneWidget);
  });
}

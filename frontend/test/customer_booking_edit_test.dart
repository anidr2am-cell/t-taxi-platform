import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/features/booking/widgets/customer_booking_edit_card.dart';

void main() {
  for (final lang in ['ko', 'en', 'th', 'ja', 'zh', 'ru']) {
    testWidgets(
      '375px $lang edit form has no overflow and saves only permitted details',
      (t) async {
        t.view.physicalSize = const Size(375, 812);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        Map<String, dynamic>? sent;
        bool saved = false;
        final data = {
          'canEdit': true,
          'flightEditable': true,
          'revision': 'a' * 64,
          'phone': '+66812345678',
          'email': null,
          'messengerType': 'LINE',
          'messengerId': 'qa_line',
          'flightNumber': 'KE651',
          'specialRequests': null,
        };
        final api = CustomerBookingEditApi(
          baseUrl: 'https://qa.invalid',
          client: MockClient((r) async {
            expect(r.url.path, '/api/v1/bookings/TX209901010218/customer-edit');
            expect(r.headers['X-Guest-Access-Token'], 'qa-token');
            if (r.method == 'PATCH')
              sent = Map<String, dynamic>.from(jsonDecode(r.body));
            return http.Response(
              jsonEncode({
                'success': true,
                'data': {...data, 'changed': r.method == 'PATCH'},
              }),
              200,
            );
          }),
        );
        await t.pumpWidget(
          MaterialApp(
            locale: Locale(lang),
            supportedLocales: AppLocalizations.customerSupportedLanguages
                .map(Locale.new)
                .toList(),
            localizationsDelegates: [
              AppLocalizationsDelegate(lang),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(
              body: CustomerBookingEditCard(
                bookingNumber: 'TX209901010218',
                guestToken: 'qa-token',
                status: 'DRIVER_ASSIGNED',
                api: api,
                onSaved: (_) async {
                  saved = true;
                },
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('voucherEditOpen')));
        await t.pumpAndSettle();
        expect(
          find.text(AppLocalizations(lang).t('voucher_edit_title')),
          findsOneWidget,
        );
        expect(sent, isNull);
        await t.scrollUntilVisible(
          find.byKey(const Key('requests')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await t.enterText(find.byKey(const Key('requests')), 'QA request');
        await t.tap(find.byKey(const Key('voucherEditSave')));
        await t.pumpAndSettle();
        expect(saved, true);
        expect(sent!['specialRequests'], 'QA request');
        expect(sent!.containsKey('scheduledPickupAt'), false);
        expect(sent!.containsKey('totalAmount'), false);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets('completed voucher has no edit action', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomerBookingEditCard(
            bookingNumber: 'TX209901010218',
            guestToken: 'qa-token',
            status: 'COMPLETED',
            onSaved: (_) async {},
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('voucherEditOpen')), findsNothing);
  });
}

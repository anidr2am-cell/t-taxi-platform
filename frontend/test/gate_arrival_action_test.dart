import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/features/booking/services/gate_arrival_api.dart';
import 'package:frontend/features/booking/widgets/gate_arrival_action.dart';
import 'package:frontend/features/admin_dispatch/widgets/admin_gate_arrival_link.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Widget wrap(Widget child, String lang) => MaterialApp(
  locale: Locale(lang),
  supportedLocales: AppLocalizations.customerSupportedLanguages.map(Locale.new),
  localizationsDelegates: [
    AppLocalizationsDelegate(lang),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: SingleChildScrollView(child: child)),
);
void main() {
  for (final lang in AppLocalizations.customerSupportedLanguages) {
    testWidgets(
      'arrival confirmation at 375px $lang; GET is read only and one POST after confirmation',
      (tester) async {
        tester.view.physicalSize = const Size(375, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final requests = <http.Request>[];
        final api = GateArrivalApi(
          client: MockClient((req) async {
            requests.add(req);
            expect(
              req.url.path,
              '/api/v1/bookings/TX202611050001/gate-arrival',
            );
            expect(req.headers['X-Guest-Access-Token'], 'qa-token');
            return http.Response(
              jsonEncode({
                'success': true,
                'data': {
                  'available': true,
                  'sent': req.method == 'POST',
                  'notificationRead': false,
                },
              }),
              200,
            );
          }),
        );
        final t = AppLocalizations(lang).t;
        await tester.pumpWidget(
          wrap(
            GateArrivalAction(
              bookingNumber: 'TX202611050001',
              guestToken: 'qa-token',
              api: api,
            ),
            lang,
          ),
        );
        await tester.pumpAndSettle();
        expect(requests.map((r) => r.method), ['GET']);
        await tester.tap(find.text(t('gate_arrival_button')));
        await tester.pumpAndSettle();
        expect(find.text(t('gate_arrival_confirm_title')), findsOneWidget);
        expect(requests.length, 1);
        await tester.tap(find.text(t('gate_arrival_send')));
        await tester.pumpAndSettle();
        expect(requests.map((r) => r.method), ['GET', 'POST']);
        expect(find.text(t('gate_arrival_sent')), findsOneWidget);
        expect(find.text(t('gate_arrival_button')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('unknown HTTP response never exposes raw error', (tester) async {
    final api = GateArrivalApi(
      client: MockClient(
        (_) async => http.Response('sensitive error in server config', 500),
      ),
    );
    await tester.pumpWidget(
      wrap(GateArrivalAction(bookingNumber: 'TX202611050001', api: api), 'ko'),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(AppLocalizations('ko').t('gate_arrival_error')),
      findsOneWidget,
    );
    expect(find.textContaining('sensitive error'), findsNothing);
  });
  testWidgets(
    'admin link is selectable, locale aware, contains no auth secret',
    (tester) async {
      await tester.pumpWidget(
        wrap(const AdminGateArrivalLink(bookingNumber: 'TX202611050001'), 'ko'),
      );
      await tester.pumpAndSettle();
      final text = tester
          .widget<SelectableText>(find.byType(SelectableText))
          .data!;
      final url = Uri.parse(text);
      expect(url.host, 'trider.taxi');
      expect(url.queryParameters, {
        'bookingNumber': 'TX202611050001',
        'lang': 'ko',
        'arrival': 'gate7',
      });
      expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
    },
  );
}

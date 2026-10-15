import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/widgets/booking_review_form.dart';
import 'package:frontend/features/admin_dispatch/widgets/admin_review_request_card.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/features/admin_dispatch/services/admin_dispatch_api_service.dart';

class ReviewRequestApiFake extends AdminDispatchApiService {
  final state = <String, dynamic>{
    'eligible': true,
    'locale': 'ko',
    'status': 'NOT_REQUESTED',
    'optedOut': false,
    'googleReviewUrl': 'https://g.page/r/abc/review',
  };
  final actions = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> getReviewRequest(String number) async => state;
  @override
  Future<Map<String, dynamic>> recordReviewRequest(
    String number,
    Map<String, dynamic> body,
  ) async {
    actions.add(body);
    if (body['action'] == 'COPY') state['status'] = 'COPIED';
    if (body['action'] == 'SENT') state['status'] = 'SENT';
    if (body['action'] == 'OPT_OUT') state['optedOut'] = body['optedOut'];
    return {...state};
  }
}

Widget host(Widget child, String locale) => MaterialApp(
  locale: Locale(locale),
  supportedLocales: AppLocalizations.supportedLanguages.map((code) => Locale(code)).toList(),
  localizationsDelegates: [AppLocalizationsDelegate(locale), GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets(
    'administrator copy records only copy; resend requires confirmation and opt-out disables actions',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final api = ReviewRequestApiFake();
      await tester.pumpWidget(
        host(
          AdminReviewRequestCard(bookingNumber: 'TX202610140001', api: api),
          'ko',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('메시지 복사'));
      await tester.pumpAndSettle();
      expect(api.actions.single['action'], 'COPY');
      expect(find.text('복사함'), findsWidgets);
      await tester.tap(find.text('보냈음 표시'));
      await tester.pumpAndSettle();
      expect(api.actions.last['action'], 'SENT');
      await tester.tap(find.text('보냈음 표시'));
      await tester.pumpAndSettle();
      expect(find.text('이미 요청을 보냈습니다. 다시 보냈음으로 기록할까요?'), findsOneWidget);
      expect(api.actions.length, 2);
      await tester.tap(find.text(AppLocalizations('ko').t('admin_review_request_cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(api.actions.last, {'action': 'OPT_OUT', 'optedOut': true});
      final copyButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, '메시지 복사'),
      );
      expect(copyButton.onPressed, isNull);
    },
  );
  for (final locale in AppLocalizations.supportedLanguages) {
    test(
      'manual message $locale contains both links, no token or incentives',
      () {
        final text = reviewRequestMessage(
          locale,
          'TX202610140001',
          'https://g.page/r/abc/review',
          origin: 'https://trider.taxi',
        );
        expect(
          text,
          contains(
            'https://trider.taxi/booking/lookup?bookingNumber=TX202610140001&lang=$locale',
          ),
        );
        expect(text, contains('https://g.page/r/abc/review'));
        expect(text.indexOf('https://g.page/r/abc/review'),
            lessThan(text.indexOf('https://trider.taxi/booking/lookup')));
        expect(text, contains('😊'));
        final withoutGoogle = reviewRequestMessage(locale, 'TX202610140001', '',
            origin: 'https://trider.taxi');
        expect(withoutGoogle, isNot(contains('{googleLine}')));
        expect(withoutGoogle, isNot(contains('g.page')));
        expect(withoutGoogle, contains('/booking/lookup?'));
        expect(withoutGoogle.split('\n').length, 3);

        expect(text, isNot(contains('guestAccessToken')));
        for (final key in [
          'review_experience_title',
          'review_google_button',
          'admin_review_request_filter',
          'admin_review_request_opt_out',
        ]) {
          expect(AppLocalizations(locale).t(key), isNot(key));
        }
      },
    );
    for (final rating in [1, 5]) {
      testWidgets(
        '375px $locale submitted $rating-star review never hides Google',
        (tester) async {
          tester.view.physicalSize = const Size(375, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            host(
              BookingReviewForm(
                bookingNumber: 'TX202610140001',
                googleReviewUrl: 'https://g.page/r/abc/review',
                initialState: {
                  'eligible': true,
                  'submitted': true,
                  'rating': rating,
                },
              ),
              locale,
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('google_review_button')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('missing Google setting leaves internal review available', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const BookingReviewForm(
          bookingNumber: 'TX202610140001',
          googleReviewUrl: '',
          initialState: {'eligible': true, 'submitted': false},
        ),
        'ko',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('google_review_button')), findsNothing);
    expect(find.byKey(const ValueKey('review_rating_1')), findsOneWidget);
  });
  testWidgets('driverless or unfinished trip does not expose review actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const BookingReviewForm(
          bookingNumber: 'TX202610140001',
          googleReviewUrl: 'https://g.page/r/abc/review',
          initialState: {'eligible': false, 'submitted': false},
        ),
        'ko',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('google_review_button')), findsNothing);
    expect(find.byKey(const ValueKey('review_rating_1')), findsNothing);
  });
}

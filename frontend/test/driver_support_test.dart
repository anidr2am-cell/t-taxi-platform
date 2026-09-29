import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/models/contact_channel.dart';
import 'package:frontend/features/booking/services/booking_contact_connection_service.dart';
import 'package:frontend/features/driver/pages/driver_support_page.dart';
import 'package:frontend/l10n/app_localizations.dart';

Widget _wrap({
  Locale locale = const Locale('ko'),
  double width = 360,
  double height = 800,
  required BookingContactConnectionService contactService,
  DriverSupportUrlLauncher? launcher,
}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLanguages
        .map((code) => Locale(code))
        .toList(),
    localizationsDelegates: [
      AppLocalizationsDelegate(locale.languageCode),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, height)),
      child: DriverSupportPage(
        contactService: contactService,
        launchUrlOverride: launcher,
      ),
    ),
  );
}

void main() {
  testWidgets('driver can open the configured administrator LINE URL', (
    tester,
  ) async {
    Uri? openedUri;
    await tester.pumpWidget(
      _wrap(
        contactService: _FakeContactService(const [
          ContactChannel(
            code: 'LINE',
            displayName: 'LINE',
            addUrl: 'https://lin.ee/admin-support',
          ),
        ]),
        launcher: (uri) async {
          openedUri = uri;
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('driver_admin_line_contact_button')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('driver_admin_line_contact_button')));
    await tester.pumpAndSettle();

    expect(openedUri, Uri.parse('https://lin.ee/admin-support'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'driver sees an unavailable message when LINE is not configured',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          width: 360,
          contactService: _FakeContactService(const [
            ContactChannel(
              code: 'KAKAO',
              displayName: 'KakaoTalk',
              addUrl: 'https://open.kakao.com/example',
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('driver_admin_line_unavailable')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('driver support rejects an unsafe LINE URL', (tester) async {
    var launchCount = 0;
    await tester.pumpWidget(
      _wrap(
        contactService: _FakeContactService(const [
          ContactChannel(
            code: 'LINE',
            displayName: 'LINE',
            addUrl: 'javascript:alert(1)',
          ),
        ]),
        launcher: (_) async {
          launchCount += 1;
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('driver_admin_line_contact_button')));
    await tester.pumpAndSettle();

    expect(launchCount, 0);
    expect(find.byType(SnackBar), findsOneWidget);
  });
}

class _FakeContactService extends BookingContactConnectionService {
  _FakeContactService(this.channels);

  final List<ContactChannel> channels;

  @override
  Future<List<ContactChannel>> getPublicChannels() async => channels;
}

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/features/booking/widgets/preferred_support_button.dart';
import 'package:frontend/features/booking/widgets/booking_messenger_icon.dart';
import 'package:frontend/features/booking/models/contact_channel.dart';
import 'package:frontend/features/booking/services/booking_contact_connection_service.dart';

class _Channels extends BookingContactConnectionService {
  _Channels(this.channels);
  final List<ContactChannel> channels;
  @override
  Future<List<ContactChannel>> getPublicChannels() async => channels;
}

const channels = [
  ContactChannel(
    code: 'LINE',
    displayName: 'LINE',
    addUrl: 'https://line.me/example',
  ),
  ContactChannel(
    code: 'KAKAO',
    displayName: 'KakaoTalk',
    addUrl: 'https://pf.kakao.com/example',
  ),
  ContactChannel(
    code: 'WHATSAPP',
    displayName: 'WhatsApp',
    phoneNumber: '+66812345678',
  ),
  ContactChannel(
    code: 'WECHAT',
    displayName: 'WeChat',
    qrImageUrl: 'https://example.com/qr.jpg',
  ),
  ContactChannel(
    code: 'TELEGRAM',
    displayName: 'Telegram',
    addUrl: 'https://t.me/TRider_taxi',
  ),
];
Widget app(Widget child, String locale) => MaterialApp(
  locale: Locale(locale),
  supportedLocales: AppLocalizations.supportedLanguages
      .map(Locale.new)
      .toList(),
  localizationsDelegates: [
    AppLocalizationsDelegate(locale),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  routes: {'/support': (_) => const Scaffold(body: Text('SUPPORT_FALLBACK'))},
  home: Scaffold(body: SingleChildScrollView(child: child)),
);
void main() {
  testWidgets('WeChat uses the exact owner-supplied asset', (tester) async {
    await tester.pumpWidget(app(bookingMessengerIcon('WECHAT'), 'ko'));
    await tester.pumpAndSettle();
    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/images/brands/wechat_app_icon.png',
    );
    expect(image.width, 24);
    expect(image.height, 24);
  });
  for (final locale in ['ko', 'en', 'th', 'ja', 'zh'])
    testWidgets(
      'support picker lists all configured channels at 375px: $locale',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(375, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final opened = <Uri>[];
        await tester.pumpWidget(
          app(
            PreferredSupportButton(
              chooseChannel: true,
              service: _Channels(channels),
              launchOverride: (uri) async {
                opened.add(uri);
                return true;
              },
            ),
            locale,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(AppLocalizations(locale).t('landing_support_cta')),
        );
        await tester.pumpAndSettle();
        expect(opened, isEmpty);
        for (final channel in channels)
          expect(
            find.byKey(ValueKey('booking-support-${channel.code}')),
            findsOneWidget,
          );
        expect(tester.takeException(), isNull);
        await tester.tap(
          find.byKey(const ValueKey('booking-support-TELEGRAM')),
        );
        await tester.pumpAndSettle();
        expect(opened.single.toString(), 'https://t.me/TRider_taxi');
        await tester.tap(
          find.text(AppLocalizations(locale).t('landing_support_cta')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('booking-support-WECHAT')));
        await tester.pumpAndSettle();
        expect(
          find.text(AppLocalizations(locale).t('support_close_button')),
          findsOneWidget,
        );
        expect(opened.length, 1);
        expect(tester.takeException(), isNull);
      },
    );
  testWidgets(
    'WeChat selection shows QR without opening a different messenger',
    (tester) async {
      final opened = <Uri>[];
      await tester.pumpWidget(
        app(
          PreferredSupportButton(
            chooseChannel: true,
            service: _Channels(channels),
            launchOverride: (uri) async {
              opened.add(uri);
              return true;
            },
          ),
          'ko',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('고객센터'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('booking-support-WECHAT')));
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      expect(
        find.text(AppLocalizations('ko').t('support_wechat_qr_dialog_title')),
        findsOneWidget,
      );
      expect(
        find.text(AppLocalizations('ko').t('booking_wechat_open_qr')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('other consumers retain the preferred-channel shortcut', (
    tester,
  ) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      app(
        PreferredSupportButton(
          service: _Channels(channels),
          launchOverride: (uri) async {
            opened.add(uri);
            return true;
          },
        ),
        'ko',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('고객센터 · KakaoTalk'));
    await tester.pumpAndSettle();
    expect(opened.single.host, 'pf.kakao.com');
    expect(find.byKey(const ValueKey('booking-support-LINE')), findsNothing);
  });
  testWidgets('empty configured channels fall back safely to support', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        PreferredSupportButton(chooseChannel: true, service: _Channels([])),
        'ko',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('고객센터'));
    await tester.pumpAndSettle();
    expect(find.text('SUPPORT_FALLBACK'), findsOneWidget);
  });
}

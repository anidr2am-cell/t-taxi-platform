import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/models/contact_channel.dart';
import 'package:frontend/features/booking/services/booking_contact_connection_service.dart';
import 'package:frontend/features/support/pages/customer_support_page.dart';
import 'package:frontend/features/support/widgets/support_contact_channels_section.dart';
import 'package:frontend/l10n/app_localizations.dart';

Widget _wrapSupport({
  Locale locale = const Locale('ko'),
  double width = 360,
  double height = 900,
  BookingContactConnectionService? contactService,
  Widget? child,
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
      child: child ?? CustomerSupportPage(contactService: contactService),
    ),
  );
}

const _allChannels = [
  ContactChannel(
    code: 'KAKAO',
    displayName: 'KakaoTalk',
    addUrl: 'https://open.kakao.com/o/example',
  ),
  ContactChannel(
    code: 'LINE',
    displayName: 'LINE',
    addUrl: 'https://lin.ee/example',
    qrImageUrl: 'https://example.test/legacy-line-qr.png',
  ),
  ContactChannel(
    code: 'WHATSAPP',
    displayName: 'WhatsApp',
    phoneNumber: '66815693445',
  ),
  ContactChannel(
    code: 'WECHAT',
    displayName: 'WeChat',
    qrImageUrl: 'https://example.test/wechat-qr.png',
  ),
  ContactChannel(
    code: 'TELEGRAM',
    displayName: 'Telegram',
    addUrl: 'https://t.me/TRider_taxi',
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CustomerSupportPage', () {
    testWidgets('renders contact channels section with five icons', (
      tester,
    ) async {
      final l10n = AppLocalizations('ko');
      final service = _FakeContactService(channels: _allChannels);

      await tester.pumpWidget(_wrapSupport(contactService: service));
      await tester.pumpAndSettle();

      expect(
        find.text(l10n.t('support_contact_channels_title')),
        findsOneWidget,
      );
      expect(
        find.text(l10n.t('support_contact_channels_hint')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('support_contact_channel_KAKAO')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('support_contact_channel_LINE')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('support_contact_channel_WHATSAPP')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('support_contact_channel_WECHAT')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('support_contact_channel_TELEGRAM')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('support_open_inquiry_button')),
        findsNothing,
      );
      expect(find.text(l10n.t('support_faq_placeholder')), findsNothing);
    });

    testWidgets('keeps the same contact order in Korean and Thai', (
      tester,
    ) async {
      for (final locale in [const Locale('ko'), const Locale('th')]) {
        await tester.pumpWidget(
          _wrapSupport(
            locale: locale,
            contactService: _FakeContactService(channels: _allChannels),
          ),
        );
        await tester.pumpAndSettle();
        final icons = find.byWidgetPredicate(
          (widget) =>
              widget is InkWell &&
              widget.key.toString().contains('support_contact_channel_'),
        );
        expect(
          icons.evaluate().map(
            (element) => (element.widget.key as ValueKey).value,
          ),
          [
            'WHATSAPP',
            'LINE',
            'KAKAO',
            'WECHAT',
            'TELEGRAM',
          ].map((code) => 'support_contact_channel_$code'),
        );
      }
    });

    testWidgets('LINE uses the official add URL and Telegram opens its URL', (
      tester,
    ) async {
      final opened = <Uri>[];
      await tester.pumpWidget(
        _wrapSupport(
          child: Scaffold(
            body: SupportContactChannelsSection(
              contactService: _FakeContactService(channels: _allChannels),
              launchUrlOverride: (uri) async {
                opened.add(uri);
                return true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final code in ['LINE', 'TELEGRAM']) {
        await tester.tap(find.byKey(Key('support_contact_channel_$code')));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
      }
      expect(opened.map((uri) => uri.toString()), [
        'https://lin.ee/example',
        'https://t.me/TRider_taxi',
      ]);
    });

    testWidgets('WeChat tap opens QR dialog instead of launching URL', (
      tester,
    ) async {
      final l10n = AppLocalizations('ko');
      final service = _FakeContactService(channels: _allChannels);

      await tester.pumpWidget(_wrapSupport(contactService: service));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('support_contact_channel_WECHAT')));
      await tester.pumpAndSettle();

      expect(
        find.text(l10n.t('support_wechat_qr_dialog_title')),
        findsOneWidget,
      );
      expect(
        find.text(l10n.t('support_wechat_qr_dialog_hint')),
        findsOneWidget,
      );
    });

    testWidgets('hides section when no channels are enabled', (tester) async {
      final l10n = AppLocalizations('ko');
      final service = _FakeContactService(channels: const []);

      await tester.pumpWidget(_wrapSupport(contactService: service));
      await tester.pumpAndSettle();

      expect(find.text(l10n.t('support_contact_channels_title')), findsNothing);
    });

    testWidgets('has no overflow at common widths', (tester) async {
      final service = _FakeContactService(channels: _allChannels);

      for (final width in [360.0, 768.0, 1440.0]) {
        await tester.pumpWidget(
          _wrapSupport(width: width, contactService: service),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'Page at $width');
      }
    });
  });
}

class _FakeContactService extends BookingContactConnectionService {
  _FakeContactService({required this.channels}) : super(baseUrl: 'http://test');

  final List<ContactChannel> channels;

  @override
  Future<List<ContactChannel>> getPublicChannels() async => channels;
}

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/widgets/guest_booking_lookup_inquiry_banner.dart';
import 'package:frontend/features/platform_settings/services/platform_settings_api_service.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/theme/app_theme.dart';

class _FakeGuestLookupInquiryApi extends PlatformSettingsApiService {
  @override
  Future<Map<String, dynamic>> getGuestLookupInquiry() async => {
        'enabled': true,
        'message': '관리자에게 문의하세요',
        'channels': [
          {
            'code': 'KAKAO',
            'displayName': 'KakaoTalk',
            'addUrl': 'https://open.kakao.com/o/s/example',
            'enabled': true,
          },
          {
            'code': 'LINE',
            'displayName': 'LINE',
            'addUrl': 'https://line.me/R/ti/p/@example',
            'enabled': true,
          },
        ],
      };
}

const _brandAssets = [
  'assets/images/brands/kakao_talk_app_icon.png',
  'assets/images/brands/line_app_icon_ios.png',
];

Future<void> _decodeBrandAssetsForTest() async {
  for (final asset in _brandAssets) {
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(
      Uint8List.view(data.buffer),
    );
    final frame = await codec.getNextFrame();
    expect(frame.image.width, greaterThan(0));
    frame.image.dispose();
    codec.dispose();
  }
}

Future<void> _precacheBrandIcons(WidgetTester tester) async {
  final context = tester.element(find.byType(MaterialApp));
  for (final asset in _brandAssets) {
    await tester.runAsync(() => precacheImage(AssetImage(asset), context));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_decodeBrandAssetsForTest);

  testWidgets('golden: inquiry banner with Kakao and LINE icons at 375px', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: [
          AppLocalizationsDelegate('ko'),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLanguages
            .map((code) => Locale(code))
            .toList(),
        locale: const Locale('ko'),
        home: Scaffold(
          backgroundColor: const Color(0xFFF5F5F5),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: RepaintBoundary(
                key: const Key('guest_lookup_inquiry_banner_capture'),
                child: GuestBookingLookupInquiryBanner(
                  api: _FakeGuestLookupInquiryApi(),
                  launchUrlOverride: (_) async => true,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // FutureBuilder resolves on next microtask; avoid pumpAndSettle hang.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await _precacheBrandIcons(tester);
    await tester.pump();

    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images.length, greaterThanOrEqualTo(2));
    expect(
      images.map((w) => (w.image as AssetImage?)?.assetName).whereType<String>(),
      containsAll(_brandAssets),
    );

    await expectLater(
      find.byKey(const Key('guest_lookup_inquiry_banner_capture')),
      matchesGoldenFile('goldens/guest_lookup_inquiry_banner_375.png'),
    );
  });
}

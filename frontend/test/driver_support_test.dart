import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver/pages/driver_support_page.dart';
import 'package:frontend/features/platform_settings/services/platform_settings_api_service.dart';
import 'package:frontend/l10n/app_localizations.dart';

Widget _wrap({
  Locale locale = const Locale('ko'),
  double width = 360,
  double height = 800,
  required PlatformSettingsApiService api,
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
      child: DriverSupportPage(api: api),
    ),
  );
}

void main() {
  testWidgets('driver support renders LINE description and QR image safely', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        api: const _FakePlatformSettingsApi({
          'lineQrDescription': 'LINE 기사 지원 안내\n운영팀 연결',
          'lineQrImageUrl': '/api/v1/settings/assets/lineQr',
        }),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('LINE 기사 지원 안내\n운영팀 연결'), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.errorBuilder, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'driver support shows fallback without QR and has no mobile overflow',
    (tester) async {
      final l10n = AppLocalizations('ko');
      await tester.pumpWidget(
        _wrap(
          width: 360,
          api: const _FakePlatformSettingsApi({
            'lineQrDescription': 'LINE 안내',
            'lineQrImageUrl': null,
          }),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('LINE 안내'), findsOneWidget);
      expect(find.text(l10n.t('support_line_qr_missing')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _FakePlatformSettingsApi extends PlatformSettingsApiService {
  const _FakePlatformSettingsApi(this.publicSettings);

  final Map<String, dynamic> publicSettings;

  @override
  Future<Map<String, dynamic>> getPublic() async => publicSettings;

  @override
  Uri assetUri(String path) => Uri.parse('https://example.test$path');
}

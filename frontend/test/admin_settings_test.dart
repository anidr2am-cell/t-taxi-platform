import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/admin_settings/pages/admin_settings_page.dart';
import 'package:frontend/features/platform_settings/services/platform_settings_api_service.dart';
import 'package:frontend/l10n/app_localizations.dart';

const _transparentPng = <int>[
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1f,
  0x15,
  0xc4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0a,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9c,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0d,
  0x0a,
  0x2d,
  0xb4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4e,
  0x44,
  0xae,
  0x42,
  0x60,
  0x82,
];

Widget _wrap({
  required PlatformSettingsApiService api,
  Future<PlatformFile?> Function()? pickImageFile,
  double width = 390,
  double height = 900,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLanguages
        .map((code) => Locale(code))
        .toList(),
    localizationsDelegates: [
      AppLocalizationsDelegate('en'),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, height)),
      child: Scaffold(
        body: AdminSettingsPage(api: api, pickImageFile: pickImageFile),
      ),
    ),
  );
}

PlatformFile _file({String path = r'C:\not-for-preview\line.png'}) =>
    PlatformFile(
      name: 'qr.png',
      size: _transparentPng.length,
      bytes: Uint8List.fromList(_transparentPng),
      path: path,
    );

Future<void> _tapUpload(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byKey(Key(key)),
      matching: find.byType(OutlinedButton),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'file select shows immediate Image.memory preview without path URL',
    (tester) async {
      final completer = Completer<Map<String, dynamic>>();
      final api = _FakePlatformSettingsApi(uploadCompleter: completer);

      await tester.pumpWidget(
        _wrap(api: api, pickImageFile: () async => _file()),
      );
      await tester.pumpAndSettle();

      await _tapUpload(tester, 'admin_settings_upload_line_qr');

      expect(
        find.byKey(const Key('admin_settings_memory_preview_lineQrImageUrl')),
        findsOneWidget,
      );
      final memoryImage = tester.widget<Image>(
        find.byKey(const Key('admin_settings_memory_preview_lineQrImageUrl')),
      );
      expect(memoryImage.image, isA<MemoryImage>());
      expect(find.textContaining('not-for-preview'), findsNothing);

      completer.complete({
        'lineQrImageUrl': '/api/v1/settings/assets/lineQr?v=new123abc456',
        'promptPayQrImageUrl': null,
      });
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'LINE QR upload success swaps preview to persisted server image',
    (tester) async {
      final api = _FakePlatformSettingsApi();

      await tester.pumpWidget(
        _wrap(api: api, pickImageFile: () async => _file()),
      );
      await tester.pumpAndSettle();
      await _tapUpload(tester, 'admin_settings_upload_line_qr');
      await tester.pumpAndSettle();

      expect(api.uploadedKinds, ['lineQr']);
      expect(
        find.byKey(const Key('admin_settings_memory_preview_lineQrImageUrl')),
        findsNothing,
      );
      final image = tester.widget<Image>(
        find.byKey(const Key('admin_settings_network_preview_lineQrImageUrl')),
      );
      expect(
        (image.image as NetworkImage).url,
        contains('lineQr?v=line123abc456'),
      );
    },
  );

  testWidgets('PromptPay QR upload success updates the PromptPay preview', (
    tester,
  ) async {
    final api = _FakePlatformSettingsApi();

    await tester.pumpWidget(
      _wrap(api: api, pickImageFile: () async => _file()),
    );
    await tester.pumpAndSettle();
    await _tapUpload(tester, 'admin_settings_upload_promptpay_qr');
    await tester.pumpAndSettle();

    expect(api.uploadedKinds, ['promptPayQr']);
    final image = tester.widget<Image>(
      find.byKey(
        const Key('admin_settings_network_preview_promptPayQrImageUrl'),
      ),
    );
    expect(
      (image.image as NetworkImage).url,
      contains('promptPayQr?v=prompt123abc'),
    );
  });

  testWidgets('admin settings reload renders persisted QR preview', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        api: _FakePlatformSettingsApi(
          initial: const {
            'lineQrImageUrl': '/api/v1/settings/assets/lineQr?v=persisted123',
            'promptPayQrImageUrl': null,
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final image = tester.widget<Image>(
      find.byKey(const Key('admin_settings_network_preview_lineQrImageUrl')),
    );
    expect((image.image as NetworkImage).url, contains('persisted123'));
  });

  testWidgets('upload failure clears local preview and does not show success', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        api: _FakePlatformSettingsApi(uploadError: Exception('Upload failed')),
        pickImageFile: () async => _file(),
      ),
    );
    await tester.pumpAndSettle();

    await _tapUpload(tester, 'admin_settings_upload_line_qr');
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('admin_settings_memory_preview_lineQrImageUrl')),
      findsNothing,
    );
    expect(find.text('Settings saved'), findsNothing);
    expect(find.textContaining('Upload failed'), findsOneWidget);
  });

  testWidgets('network image has a broken-image fallback', (tester) async {
    await tester.pumpWidget(
      _wrap(
        api: _FakePlatformSettingsApi(
          initial: const {
            'lineQrImageUrl': '/api/v1/settings/assets/lineQr?v=broken',
            'promptPayQrImageUrl': null,
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final finder = find.byKey(
      const Key('admin_settings_network_preview_lineQrImageUrl'),
    );
    final image = tester.widget<Image>(finder);
    expect(image.errorBuilder, isNotNull);
    final fallback = image.errorBuilder!(
      tester.element(finder),
      Exception('network failed'),
      StackTrace.empty,
    );
    expect(
      find.byKey(const Key('admin_settings_image_fallback_lineQrImageUrl')),
      findsOneWidget,
    );
    expect(fallback, isA<Container>());
  });

  testWidgets('admin settings page has no overflow at 360px width', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        width: 360,
        api: _FakePlatformSettingsApi(
          initial: const {
            'lineQrDescription': 'LINE QR description',
            'bankName': 'Bank',
            'accountName': 'Account holder',
            'accountNumber': '1234',
            'promptPayNumber': '0000',
            'lineQrImageUrl': '/api/v1/settings/assets/lineQr?v=small',
            'promptPayQrImageUrl':
                '/api/v1/settings/assets/promptPayQr?v=small',
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}

class _FakePlatformSettingsApi extends PlatformSettingsApiService {
  _FakePlatformSettingsApi({
    Map<String, dynamic>? initial,
    this.uploadError,
    this.uploadCompleter,
  }) : settings = {
         'lineQrDescription': '',
         'bankName': '',
         'accountName': '',
         'accountNumber': '',
         'promptPayNumber': '',
         'lineQrImageUrl': null,
         'promptPayQrImageUrl': null,
         ...?initial,
       };

  Map<String, dynamic> settings;
  final Object? uploadError;
  final Completer<Map<String, dynamic>>? uploadCompleter;
  final uploadedKinds = <String>[];

  @override
  Future<Map<String, dynamic>> getAdmin() async => settings;

  @override
  Future<Map<String, dynamic>> update(Map<String, String> values) async =>
      settings;

  @override
  Future<Map<String, dynamic>> uploadImage(
    String kind,
    Uint8List bytes,
    String filename,
  ) async {
    uploadedKinds.add(kind);
    if (uploadError != null) throw uploadError!;
    if (uploadCompleter != null) {
      settings = await uploadCompleter!.future;
      return settings;
    }
    settings = {
      ...settings,
      if (kind == 'lineQr')
        'lineQrImageUrl': '/api/v1/settings/assets/lineQr?v=line123abc456',
      if (kind == 'promptPayQr')
        'promptPayQrImageUrl':
            '/api/v1/settings/assets/promptPayQr?v=prompt123abc',
    };
    return settings;
  }

  @override
  Uri assetUri(String path) => Uri.parse('https://example.test$path');
}

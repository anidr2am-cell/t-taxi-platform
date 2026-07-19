import 'dart:async';
import 'dart:convert';
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

final _jpegBytes = base64Decode(
  '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoH'
  'BwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/2wBDAQME'
  'BAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQU'
  'FBQUFBQUFBQUFBQUFBT/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQ'
  'EAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQR'
  'BRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY'
  '3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJ'
  'WWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5'
  'ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQ'
  'oL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKR'
  'obHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVld'
  'YWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsr'
  'O0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oA'
  'DAMBAAIRAxEAPwD9U6KKKAP/2Q==',
);

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

PlatformFile _file({
  String name = 'qr.png',
  List<int> bytes = _transparentPng,
  String path = r'C:\not-for-preview\line.png',
}) => PlatformFile(
  name: name,
  size: bytes.length,
  bytes: Uint8List.fromList(bytes),
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
  test('settings image content type is inferred from safe PNG/JPEG bytes', () {
    expect(
      settingsImageContentTypeFor(
        'line.png',
        Uint8List.fromList(_transparentPng),
      ).toString(),
      'image/png',
    );
    expect(
      settingsImageContentTypeFor(
        'promptpay.jpg',
        Uint8List.fromList(_jpegBytes),
      ).toString(),
      'image/jpeg',
    );
  });

  test(
    'settings image content type rejects HEIC, PDF, SVG, and fake images',
    () {
      for (final entry in [
        MapEntry('phone.heic', [
          0x00,
          0x00,
          0x00,
          0x18,
          0x66,
          0x74,
          0x79,
          0x70,
        ]),
        MapEntry('document.pdf', '%PDF-1.7'.codeUnits),
        MapEntry('vector.svg', '<svg></svg>'.codeUnits),
        MapEntry('fake.png', 'not an image'.codeUnits),
        MapEntry('wrong.jpg', _transparentPng),
      ]) {
        expect(
          settingsImageContentTypeFor(
            entry.key,
            Uint8List.fromList(entry.value),
          ),
          isNull,
        );
      }
    },
  );

  test(
    'settings upload pre-validates unsupported files before token lookup',
    () async {
      await expectLater(
        const PlatformSettingsApiService().uploadImage(
          'lineQr',
          Uint8List.fromList('%PDF-1.7'.codeUnits),
          'qr.pdf',
        ),
        throwsA(
          isA<PlatformSettingsApiException>().having(
            (error) => error.errorCode,
            'errorCode',
            'INVALID_SETTINGS_IMAGE',
          ),
        ),
      );
    },
  );

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

  testWidgets('JPEG file select shows immediate Image.memory preview', (
    tester,
  ) async {
    final completer = Completer<Map<String, dynamic>>();
    final api = _FakePlatformSettingsApi(uploadCompleter: completer);

    await tester.pumpWidget(
      _wrap(
        api: api,
        pickImageFile: () async => _file(name: 'qr.jpg', bytes: _jpegBytes),
      ),
    );
    await tester.pumpAndSettle();

    await _tapUpload(tester, 'admin_settings_upload_line_qr');

    expect(
      find.byKey(const Key('admin_settings_memory_preview_lineQrImageUrl')),
      findsOneWidget,
    );

    completer.complete({
      'lineQrImageUrl': '/api/v1/settings/assets/lineQr?v=jpeg123abc45',
      'promptPayQrImageUrl': null,
    });
    await tester.pumpAndSettle();
  });

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
        api: _FakePlatformSettingsApi(
          uploadError: const PlatformSettingsApiException(
            'Only PNG and JPEG images are supported',
            errorCode: 'INVALID_SETTINGS_IMAGE',
            statusCode: 400,
          ),
        ),
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
    expect(find.text('Please choose a PNG or JPG image file.'), findsOneWidget);
    expect(find.textContaining('Exception:'), findsNothing);
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

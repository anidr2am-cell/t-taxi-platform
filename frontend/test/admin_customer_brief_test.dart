import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/features/admin_dispatch/utils/admin_customer_brief.dart';
import 'package:frontend/features/admin_dispatch/widgets/admin_customer_brief_card.dart';
import 'package:frontend/features/admin_dispatch/widgets/admin_driver_detail_dialog.dart';
import 'package:frontend/features/admin_dispatch/services/admin_dispatch_api_service.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> sample({bool assigned = true}) => {
  'bookingNumber': 'TX209901010206',
  'scheduledPickupAt': '2026-11-10T16:40:00.000Z',
  'route': {
    'origin': {'name': 'QA Airport', 'nameKo': 'QA 공항'},
    'destination': {'name': 'QA Hotel'},
  },
  'specialRequests': 'QA child seat request',
  'flight': {'flightNumber': 'QA123'},
  'customer': {'phone': 'PRIVATE_CUSTOMER', 'email': 'PRIVATE_EMAIL'},
  'driverFinancialSummary': {'commissionAmount': 'PRIVATE_FINANCE'},
  'activeAssignment': assigned
      ? {
          'assignmentId': 1,
          'isActive': true,
          'driverDisplayName': 'QA Driver',
          'driverPhone': 'QA_PHONE',
          'vehicle': {
            'modelName': 'QA Sedan',
            'plateNumber': 'QA123',
            'color': 'White',
          },
        }
      : null,
};

class Api extends AdminDispatchApiService {
  int photoCalls = 0;
  @override
  Future<List<dynamic>> getCustomerBriefPhotos(String n) async {
    photoCalls++;
    return [
      {'fileId': 8, 'mimeType': 'image/png'},
    ];
  }

  @override
  Future<Uint8List> getCustomerBriefPhoto(
    String n,
    int id,
  ) async => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
  );
  @override
  Future<Map<String, dynamic>> getDriverDetail(int id) async => {
    'driverId': id,
    'displayName': 'QA Driver',
    'phone': 'QA_PHONE',
    'driverStatus': 'OFFLINE',
    'onlineState': 'OFFLINE',
    'activeAssignmentCount': 1,
    'vehicles': [
      {'modelName': 'QA Sedan', 'plateNumber': 'QA123', 'isPrimary': true},
    ],
  };
}

Widget host(Widget child, {String lang = 'ko'}) => MaterialApp(
  locale: Locale(lang),
  supportedLocales: AppLocalizations.supportedLanguages.map(Locale.new),
  localizationsDelegates: [
    AppLocalizationsDelegate(lang),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: SingleChildScrollView(child: child)),
);
void main() {
  test(
    'customer brief uses Bangkok time and excludes private internal fields',
    () {
      final text = buildAdminCustomerBrief(sample(), 'ko');
      expect(text, contains('2026-11-10 23:40'));
      expect(text, contains('QA123'));
      expect(text, contains('QA child seat request'));
      expect(text, contains('QA 공항'));
      expect(text, isNot(contains('PRIVATE')));
      expect(buildAdminCustomerBrief(sample(assigned: false), 'ko'), '');
    },
  );
  for (final lang in AppLocalizations.supportedLanguages) {
    testWidgets('customer brief 375px / copy / download in $lang', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? copied;
      await tester.pumpWidget(
        host(
          AdminCustomerBriefCard(
            detail: sample(),
            api: Api(),
            copyText: (s) async => copied = s,
          ),
          lang: lang,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.copy_outlined));
      await tester.pumpAndSettle();
      expect(copied, contains('QA123'));
      expect(find.textContaining('2026-11-10 23:40'), findsOneWidget);
      expect(tester.takeException(), null);
    });
  }
  testWidgets(
    'unassigned disables text / photo functions and performs no photo reads',
    (tester) async {
      final api = Api();
      await tester.pumpWidget(
        host(AdminCustomerBriefCard(detail: sample(assigned: false), api: api)),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<IconButton>(find.byType(IconButton).first).onPressed,
        null,
      );
      for (final button in tester.widgetList<OutlinedButton>(
        find.byType(OutlinedButton),
      ))
        expect(button.onPressed, null);
      expect(api.photoCalls, 0);
    },
  );
  testWidgets('driver detail loads in a scrollable read-only dialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => AdminDriverDetailDialog(driverId: 6, api: Api()),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('QA Driver'), findsOneWidget);
    expect(find.textContaining('QA123'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), null);
  });
  test('API uses exact authenticated admin URLs; no writes', () async {
    SharedPreferences.setMockInitialValues({'admin_access_token': 'QA_ONLY'});
    final requests = <String>[];
    final api = AdminDispatchApiService(
      baseUrl: 'https://qa.invalid',
      client: MockClient((r) async {
        expect(r.method, 'GET');
        expect(r.headers['Authorization'], 'Bearer QA_ONLY');
        requests.add(r.url.path);
        if (r.url.path.endsWith('/8'))
          return http.Response.bytes(
            [1, 2],
            200,
            headers: {'content-type': 'image/png'},
          );
        return http.Response(
          jsonEncode({
            'success': true,
            'data': r.url.path.endsWith('photos') ? [] : {'driverId': 6},
          }),
          200,
        );
      }),
    );
    await api.getDriverDetail(6);
    await api.getCustomerBriefPhotos('TX209901010206');
    await api.getCustomerBriefPhoto('TX209901010206', 8);
    expect(requests, [
      '/api/v1/admin/drivers/6',
      '/api/v1/admin/bookings/TX209901010206/customer-brief/photos',
      '/api/v1/admin/bookings/TX209901010206/customer-brief/photos/8',
    ]);
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/admin_driver_application/pages/admin_driver_application_detail_page.dart';
import 'package:frontend/features/admin_driver_application/pages/admin_driver_application_list_page.dart';
import 'package:frontend/features/driver/pages/driver_login_page.dart';
import 'package:frontend/features/driver/services/driver_api_service.dart';
import 'package:frontend/features/driver_application/models/driver_application_models.dart';
import 'package:frontend/features/driver_application/pages/driver_application_status_page.dart';
import 'package:frontend/features/driver_application/services/driver_application_api_service.dart';
import 'package:frontend/features/driver_application/services/driver_application_storage.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

DriverApplicationDraft _draft() => const DriverApplicationDraft(
  fullName: 'Driver Kim',
  password: 'strongpass123',
  passwordConfirm: 'strongpass123',
  phone: '+66123456789',
  phoneCountryCode: '+66',
  countryCode: 'TH',
  locale: 'ko',
  drivingLicenseNumber: 'DL12345',
  drivingLicenseCountry: 'TH',
  drivingLicenseExpiryDate: '2030-01-01',
  yearsOfDrivingExperience: 5,
  vehicleOwnershipType: 'OWNED',
  vehicleTypeCode: 'SEDAN',
  vehicleTypeId: 1,
  vehicleMake: 'Toyota',
  vehicleModel: 'Camry',
  vehicleYear: 2022,
  vehicleColor: 'White',
  vehiclePlateNumber: 'AB1234',
  serviceAreas: ['Bangkok', 'Pattaya'],
  languages: ['ko', 'en'],
  notes: 'Airport transfers',
  bankName: 'Kasikorn',
  bankAccountNumber: '1234567890',
  bankAccountHolder: 'Driver Kim',
  lineId: '@driverkim',
  primaryServiceArea: 'Bangkok',
  files: DriverApplicationFileBundle(
    lineQr: DriverApplicationUploadFile(name: 'line.png', bytes: [1]),
    vehiclePhotos: [
      DriverApplicationUploadFile(name: 'car1.jpg', bytes: [1]),
      DriverApplicationUploadFile(name: 'car2.jpg', bytes: [2]),
      DriverApplicationUploadFile(name: 'car3.jpg', bytes: [3]),
    ],
    insuranceCertificate: DriverApplicationUploadFile(
      name: 'insurance.pdf',
      bytes: [1],
    ),
    vehicleRegistration: DriverApplicationUploadFile(
      name: 'registration.pdf',
      bytes: [1],
    ),
    taxCertificate: DriverApplicationUploadFile(name: 'tax.pdf', bytes: [1]),
  ),
  personalDataConsent: true,
  driverTermsConsent: true,
);

Map<String, dynamic> _envelope(Object data) => {
  'success': true,
  'message': 'OK',
  'data': data,
};

Widget _app(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLanguages.map(Locale.new),
    localizationsDelegates: [AppLocalizationsDelegate('en')],
    routes: {
      '/driver': (_) => const Scaffold(body: Text('Driver login route')),
      '/driver/apply': (_) => const Scaffold(body: Text('Apply route')),
      '/driver/application-status': (_) =>
          const Scaffold(body: Text('Status route')),
    },
    home: child,
  );
}

Widget _appScaffold(Widget child) => _app(Scaffold(body: child));

class _CaptureClient extends http.BaseClient {
  _CaptureClient(this.handler);

  final Future<http.Response> Function(http.BaseRequest request, String body)
  handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().bytesToString();
    final response = await handler(request, body);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

class _FakeDriverApi extends DriverApiService {
  const _FakeDriverApi();

  @override
  Future<String?> getSavedToken() async => null;
}

class _FakeDriverApplicationApi extends DriverApplicationApiService {
  _FakeDriverApplicationApi({
    this.status = 'PENDING',
    this.items = const [],
    this.detailStatus = 'PENDING',
  });

  final String status;
  final List<DriverApplicationAdminListItem> items;
  final String detailStatus;
  int approveCalls = 0;
  int rejectCalls = 0;

  @override
  Future<DriverApplicationStatusResult> getApplicationStatus({
    required String applicationNumber,
    required String token,
  }) async {
    return DriverApplicationStatusResult(
      applicationNumber: applicationNumber,
      status: status,
      submittedAt: '2026-07-03 10:00:00',
      reviewedAt: status == 'PENDING' ? null : '2026-07-03 11:00:00',
      rejectionReason: status == 'REJECTED' ? 'License expired' : null,
    );
  }

  @override
  Future<DriverApplicationAdminListResult> listAdminApplications({
    String? status,
    String? countryCode,
    String? vehicleTypeCode,
    String? dateFrom,
    String? dateTo,
    String? search,
    int page = 1,
    int limit = 20,
  }) async {
    return DriverApplicationAdminListResult(
      page: 1,
      pageSize: 20,
      total: items.length,
      items: items,
    );
  }

  @override
  Future<DriverApplicationAdminDetail> getAdminApplicationDetail(int id) async {
    return DriverApplicationAdminDetail(
      id: id,
      applicationNumber: 'DA260703A1B2C3D4',
      status: detailStatus,
      email: 'driver@example.com',
      fullName: 'Driver Kim',
      phone: '+66123456789',
      countryCode: 'TH',
      locale: 'ko',
      vehicleTypeCode: 'SEDAN',
      vehiclePlateNumber: 'AB1234',
      primaryServiceArea: 'Bangkok',
      submittedAt: '2026-07-03 10:00:00',
      reviewedAt: detailStatus == 'PENDING' ? null : '2026-07-03 11:00:00',
      phoneCountryCode: '+66',
      drivingLicenseNumber: 'DL12345',
      drivingLicenseCountry: 'TH',
      drivingLicenseExpiryDate: '2030-01-01',
      yearsOfDrivingExperience: 5,
      vehicleOwnershipType: 'OWNED',
      vehicleMake: 'Toyota',
      vehicleModel: 'Camry',
      vehicleYear: 2022,
      vehicleColor: 'White',
      serviceAreas: const ['Bangkok'],
      languages: const ['ko'],
      notes: 'Ready',
      bankName: 'Kasikorn',
      bankAccountNumber: '1234567890',
      bankAccountHolder: 'Driver Kim',
      lineId: '@driverkim',
      files: const [],
      personalDataConsentAt: '2026-07-03 10:00:00',
      driverTermsConsentAt: '2026-07-03 10:00:00',
      rejectionReason: detailStatus == 'REJECTED' ? 'License expired' : null,
      adminNote: detailStatus == 'REJECTED' ? 'Internal note' : null,
      approvedUserId: detailStatus == 'APPROVED' ? 100 : null,
      approvedDriverId: detailStatus == 'APPROVED' ? 200 : null,
      resubmittedFromApplicationId: null,
    );
  }

  @override
  Future<Map<String, dynamic>> approveApplication(int id) async {
    approveCalls += 1;
    return {'status': 'APPROVED'};
  }

  @override
  Future<Map<String, dynamic>> rejectApplication(
    int id, {
    required String rejectionReason,
    String? adminNote,
  }) async {
    rejectCalls += 1;
    return {'status': 'REJECTED'};
  }
}

void main() {
  test(
    'submit application uses exact public path and request payload',
    () async {
      late http.BaseRequest captured;
      final api = DriverApplicationApiService(
        baseUrl: 'http://localhost:3000',
        client: _CaptureClient((request, bodyText) async {
          captured = request;
          expect(bodyText, contains('name="applicantName"'));
          expect(bodyText, contains('Driver Kim'));
          expect(bodyText, contains('name="passwordConfirmation"'));
          expect(bodyText, contains('strongpass123'));
          expect(bodyText, contains('name="vehicleTypeCode"'));
          expect(bodyText, contains('SEDAN'));
          return http.Response(
            jsonEncode(
              _envelope({
                'applicationNumber': 'DA260703A1B2C3D4',
                'status': 'PENDING',
                'statusToken': 'raw-token',
                'submittedAt': '2026-07-03 10:00:00',
              }),
            ),
            201,
          );
        }),
      );

      final result = await api.submitApplication(_draft());

      expect(captured.method, 'POST');
      expect(captured.url.path, '/api/v1/driver-applications');
      expect(result.applicationNumber, 'DA260703A1B2C3D4');
      expect(result.statusToken, 'raw-token');
    },
  );

  test('status lookup and resubmit use API contract paths', () async {
    final paths = <String>[];
    final api = DriverApplicationApiService(
      baseUrl: 'http://localhost:3000',
      client: _CaptureClient((request, bodyText) async {
        paths.add('${request.method} ${request.url.path}');
        if (request.method == 'GET') {
          expect(
            request.url.queryParameters['applicationNumber'],
            'DA260703A1B2C3D4',
          );
          expect(request.url.queryParameters['token'], 'raw-token');
          return http.Response(
            jsonEncode(
              _envelope({
                'applicationNumber': 'DA260703A1B2C3D4',
                'status': 'REJECTED',
                'submittedAt': '2026-07-03 10:00:00',
                'reviewedAt': '2026-07-03 11:00:00',
                'rejectionReason': 'License expired',
              }),
            ),
            200,
          );
        }
        expect(bodyText, contains('name="token"'));
        expect(bodyText, contains('raw-token'));
        return http.Response(
          jsonEncode(
            _envelope({
              'applicationNumber': 'DA260704B1B2C3D4',
              'status': 'PENDING',
              'statusToken': 'new-token',
              'submittedAt': '2026-07-04 10:00:00',
            }),
          ),
          201,
        );
      }),
    );

    final status = await api.getApplicationStatus(
      applicationNumber: 'DA260703A1B2C3D4',
      token: 'raw-token',
    );
    final receipt = await api.resubmitApplication(
      applicationNumber: 'DA260703A1B2C3D4',
      token: 'raw-token',
      draft: _draft(),
    );

    expect(status.status, 'REJECTED');
    expect(receipt.statusToken, 'new-token');
    expect(paths, [
      'GET /api/v1/driver-applications/status',
      'POST /api/v1/driver-applications/DA260703A1B2C3D4/resubmit',
    ]);
  });

  test('local storage stores number token and submitted time', () async {
    SharedPreferences.setMockInitialValues({});
    const storage = DriverApplicationStorage();

    await storage.save(
      const DriverApplicationReceipt(
        applicationNumber: 'DA260703A1B2C3D4',
        status: 'PENDING',
        statusToken: 'raw-token',
        submittedAt: '2026-07-03 10:00:00',
      ),
    );

    final saved = await storage.load();
    expect(saved?.applicationNumber, 'DA260703A1B2C3D4');
    expect(saved?.statusToken, 'raw-token');
    expect(saved?.submittedAt, '2026-07-03 10:00:00');
  });

  testWidgets('driver login shows application CTAs', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_app(const DriverLoginPage(api: _FakeDriverApi())));
    await tester.pumpAndSettle();

    expect(find.text('Apply as a driver'), findsOneWidget);
    expect(find.text('Check application status'), findsOneWidget);
  });

  testWidgets('driver login application CTAs navigate to registered routes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_app(const DriverLoginPage(api: _FakeDriverApi())));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Apply as a driver'));
    await tester.pumpAndSettle();
    expect(find.text('Apply route'), findsOneWidget);

    Navigator.of(tester.element(find.text('Apply route'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Check application status'));
    await tester.pumpAndSettle();
    expect(find.text('Status route'), findsOneWidget);
  });

  testWidgets(
    'driver login CTAs stay visible without overflow on small screen',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _app(const DriverLoginPage(api: _FakeDriverApi())),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Apply as a driver'), findsOneWidget);
      expect(find.text('Check application status'), findsOneWidget);
    },
  );

  testWidgets('status page renders rejected reason and resubmit CTA', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'driver_application_number': 'DA260703A1B2C3D4',
      'driver_application_status_token': 'raw-token',
    });
    await tester.pumpWidget(
      _app(
        DriverApplicationStatusPage(
          api: _FakeDriverApplicationApi(status: 'REJECTED'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rejected'), findsWidgets);
    expect(find.text('License expired'), findsOneWidget);
    expect(find.text('Edit and resubmit'), findsOneWidget);
  });

  testWidgets('admin list renders pending approved and rejected states', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'admin_access_token': 'admin-token',
    });
    final items = ['PENDING', 'APPROVED', 'REJECTED'].map((status) {
      return DriverApplicationAdminListItem(
        id: status.hashCode,
        applicationNumber: 'DA$status',
        status: status,
        email: '$status@example.com',
        fullName: 'Driver $status',
        phone: '+66',
        countryCode: 'TH',
        locale: 'ko',
        vehicleTypeCode: 'SEDAN',
        vehiclePlateNumber: 'AB$status',
        primaryServiceArea: 'Bangkok',
        submittedAt: '2026-07-03',
        reviewedAt: null,
      );
    }).toList();

    await tester.pumpWidget(
      _appScaffold(
        AdminDriverApplicationListPage(
          api: _FakeDriverApplicationApi(items: items),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Under review'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Rejected'), findsOneWidget);
  });

  testWidgets('processed admin detail hides approve and reject actions', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'admin_access_token': 'admin-token',
    });
    await tester.pumpWidget(
      _app(
        AdminDriverApplicationDetailPage(
          id: 1,
          api: _FakeDriverApplicationApi(detailStatus: 'APPROVED'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Approved'), findsWidgets);
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Reject'), findsNothing);
  });
}

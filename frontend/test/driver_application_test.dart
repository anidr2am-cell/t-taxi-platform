import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/admin_driver_application/pages/admin_driver_application_detail_page.dart';
import 'package:frontend/features/admin_driver_application/pages/admin_driver_application_list_page.dart';
import 'package:frontend/features/driver/pages/driver_login_page.dart';
import 'package:frontend/features/driver/services/driver_api_service.dart';
import 'package:frontend/features/driver_application/models/driver_application_models.dart';
import 'package:frontend/features/driver_application/pages/driver_application_form_page.dart';
import 'package:frontend/features/driver_application/services/driver_application_api_service.dart';
import 'package:frontend/features/driver_application/services/driver_application_storage.dart';
import 'package:frontend/features/driver_application/widgets/driver_registration_photo_upload_card.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

DriverApplicationDraft _draft({DriverApplicationFileBundle? files}) =>
    DriverApplicationDraft(
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
      files:
          files ??
          const DriverApplicationFileBundle(
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
            taxCertificate: DriverApplicationUploadFile(
              name: 'tax.pdf',
              bytes: [1],
            ),
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
    },
    home: child,
  );
}

Widget _appScaffold(Widget child) => _app(Scaffold(body: child));

String _ymd(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

Future<Finder> _visibleLicenseExpiryField(WidgetTester tester) async {
  final picker = find.byIcon(Icons.calendar_today_outlined);
  await tester.scrollUntilVisible(
    picker,
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  return find.ancestor(of: picker, matching: find.byType(TextFormField));
}

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
    this.items = const [],
    this.detailStatus = 'PENDING',
  });

  final List<DriverApplicationAdminListItem> items;
  final String detailStatus;
  int approveCalls = 0;
  int rejectCalls = 0;
  int submitCalls = 0;

  @override
  Future<List<DriverApplicationVehicleType>> listVehicleTypes() async {
    return const [
      DriverApplicationVehicleType(id: 1, code: 'SEDAN', name: 'Sedan'),
    ];
  }

  @override
  Future<DriverApplicationReceipt> submitApplication(
    DriverApplicationDraft draft,
  ) async {
    submitCalls += 1;
    return const DriverApplicationReceipt(
      applicationNumber: 'DA260704B1B2C3D4',
      status: 'PENDING',
      statusToken: 'token',
      submittedAt: '2026-07-04 10:00:00',
    );
  }

  @override
  Future<DriverApplicationStatusResult> getApplicationStatus({
    required String applicationNumber,
    required String token,
  }) async {
    return DriverApplicationStatusResult(
      applicationNumber: applicationNumber,
      status: 'PENDING',
      submittedAt: '2026-07-03 10:00:00',
      reviewedAt: null,
      rejectionReason: null,
    );
  }

  @override
  Future<DriverApplicationAdminListResult> listAdminApplications({
    String? view,
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

class _FieldErrorDriverApplicationApi extends _FakeDriverApplicationApi {
  @override
  Future<DriverApplicationReceipt> submitApplication(
    DriverApplicationDraft draft,
  ) async {
    throw const DriverApplicationApiException(
      'Validation failed',
      errorCode: 'VALIDATION_ERROR',
      statusCode: 400,
      fieldErrors: {'vehicleYear': 'กรุณากรอกปีรถเป็นตัวเลข 4 หลัก เช่น 2020'},
    );
  }
}

class _UploadTooLargeDriverApplicationApi extends _FakeDriverApplicationApi {
  @override
  Future<DriverApplicationReceipt> submitApplication(
    DriverApplicationDraft draft,
  ) async {
    throw const DriverApplicationApiException(
      'Uploaded files are too large',
      errorCode: 'FILE_TOO_LARGE',
      statusCode: 413,
    );
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
          expect(bodyText, isNot(contains('name="email"')));
          expect(bodyText, contains('name="passwordConfirmation"'));
          expect(bodyText, contains('strongpass123'));
          expect(bodyText, contains('name="vehicleTypeCode"'));
          expect(bodyText, contains('SEDAN'));
          expect(bodyText, contains('content-type: image/png'));
          expect(bodyText, contains('content-type: image/jpeg'));
          expect(bodyText, contains('content-type: application/pdf'));
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

  test('submit application exposes backend field validation errors', () async {
    final api = DriverApplicationApiService(
      baseUrl: 'http://localhost:3000',
      client: _CaptureClient((request, bodyText) async {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'success': false,
              'message': 'Validation failed',
              'code': 'VALIDATION_ERROR',
              'error_code': 'VALIDATION_ERROR',
              'errors': [
                {
                  'field': 'vehicleYear',
                  'message': 'กรุณากรอกปีรถเป็นตัวเลข 4 หลัก เช่น 2020',
                },
              ],
            }),
          ),
          400,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    await expectLater(
      api.submitApplication(_draft()),
      throwsA(
        isA<DriverApplicationApiException>()
            .having((err) => err.errorCode, 'errorCode', 'VALIDATION_ERROR')
            .having(
              (err) => err.fieldErrors['vehicleYear'],
              'vehicleYear',
              contains('2020'),
            ),
      ),
    );
  });

  test(
    'submit application maps HTML 413 without leaking SyntaxError',
    () async {
      final api = DriverApplicationApiService(
        baseUrl: 'http://localhost:3000',
        client: _CaptureClient((request, bodyText) async {
          return http.Response(
            '<html><body>Request Entity Too Large</body></html>',
            413,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }),
      );

      await expectLater(
        api.submitApplication(_draft()),
        throwsA(
          isA<DriverApplicationApiException>()
              .having((err) => err.statusCode, 'statusCode', 413)
              .having((err) => err.errorCode, 'errorCode', 'FILE_TOO_LARGE')
              .having((err) => err.message, 'message', isNot(contains('<html')))
              .having(
                (err) => err.message,
                'message',
                isNot(contains('SyntaxError')),
              ),
        ),
      );
    },
  );

  test('submit application maps HTML 502 without leaking body', () async {
    final api = DriverApplicationApiService(
      baseUrl: 'http://localhost:3000',
      client: _CaptureClient((request, bodyText) async {
        return http.Response(
          '<html><body>Bad Gateway</body></html>',
          502,
          headers: {'content-type': 'text/html'},
        );
      }),
    );

    await expectLater(
      api.submitApplication(_draft()),
      throwsA(
        isA<DriverApplicationApiException>()
            .having((err) => err.statusCode, 'statusCode', 502)
            .having((err) => err.errorCode, 'errorCode', 'SERVER_UNAVAILABLE')
            .having((err) => err.message, 'message', isNot(contains('<html'))),
      ),
    );
  });

  test('submit application handles malformed JSON safely', () async {
    final api = DriverApplicationApiService(
      baseUrl: 'http://localhost:3000',
      client: _CaptureClient((request, bodyText) async {
        return http.Response(
          '{"success":true',
          201,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await expectLater(
      api.submitApplication(_draft()),
      throwsA(
        isA<DriverApplicationApiException>()
            .having((err) => err.errorCode, 'errorCode', 'REQUEST_FAILED')
            .having((err) => err.message, 'message', isNot(contains('{'))),
      ),
    );
  });

  test(
    'submit application rejects invalid file type before sending request',
    () async {
      var sent = false;
      final api = DriverApplicationApiService(
        baseUrl: 'http://localhost:3000',
        client: _CaptureClient((request, bodyText) async {
          sent = true;
          return http.Response(jsonEncode(_envelope({})), 201);
        }),
      );

      await expectLater(
        api.submitApplication(
          _draft(
            files: const DriverApplicationFileBundle(
              lineQr: DriverApplicationUploadFile(name: 'line.png', bytes: [1]),
              vehiclePhotos: [
                DriverApplicationUploadFile(name: 'car.exe', bytes: [1]),
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
              taxCertificate: DriverApplicationUploadFile(
                name: 'tax.pdf',
                bytes: [1],
              ),
            ),
          ),
        ),
        throwsA(
          isA<DriverApplicationApiException>().having(
            (err) => err.errorCode,
            'errorCode',
            'INVALID_FILE_TYPE',
          ),
        ),
      );
      expect(sent, false);
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

  test('legacy local storage can load saved status lookup data', () async {
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

  testWidgets(
    'driver apply success shows LINE guidance without storing status lookup',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = _FakeDriverApplicationApi();
      await tester.pumpWidget(
        _app(DriverApplicationFormPage(api: api, debugSubmitDraft: _draft())),
      );
      await tester.pumpAndSettle();

      final submit = find.byIcon(Icons.send_outlined);
      await tester.scrollUntilVisible(
        submit,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(api.submitCalls, 1);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.textContaining('QR Code'), findsWidgets);
      expect(find.textContaining('DA260704B1B2C3D4'), findsNothing);
      expect(find.textContaining('token'), findsNothing);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('driver_application_number'), isNull);
      expect(prefs.getString('driver_application_status_token'), isNull);
      expect(prefs.getString('driver_application_submitted_at'), isNull);
    },
  );

  testWidgets('driver login shows only application CTA', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_app(const DriverLoginPage(api: _FakeDriverApi())));
    await tester.pumpAndSettle();

    expect(find.text('기사 등록 신청 / สมัครคนขับ'), findsOneWidget);
    expect(find.text('Check application status'), findsNothing);
    expect(find.text('Check saved application status'), findsNothing);
  });

  testWidgets('driver login application CTA navigates to apply route', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_app(const DriverLoginPage(api: _FakeDriverApi())));
    await tester.pumpAndSettle();

    await tester.tap(find.text('기사 등록 신청 / สมัครคนขับ'));
    await tester.pumpAndSettle();
    expect(find.text('Apply route'), findsOneWidget);
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
      expect(find.text('기사 등록 신청 / สมัครคนขับ'), findsOneWidget);
      expect(find.text('Check application status'), findsNothing);
    },
  );

  testWidgets('driver apply page renders form controls and no Select text', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      _app(DriverApplicationFormPage(api: _FakeDriverApplicationApi())),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextFormField), findsWidgets);
    expect(find.textContaining('Select', skipOffstage: false), findsNothing);
  });

  testWidgets('driver apply renders unified upload cards for required files', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      _app(DriverApplicationFormPage(api: _FakeDriverApplicationApi())),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('driver_application_file_card_lineQr')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.byType(DriverRegistrationPhotoUploadCard), findsNWidgets(5));
    expect(
      find.byKey(const ValueKey('driver_application_file_card_lineQr')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('driver_application_file_card_vehiclePhotos')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('driver_application_file_card_insuranceCertificate'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('driver_application_file_card_vehicleRegistration'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('driver_application_file_card_taxCertificate')),
      findsOneWidget,
    );
  });

  testWidgets(
    'driver apply vehicle photos can be added incrementally and removed individually',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      var singlePickCount = 0;
      var vehiclePickCount = 0;
      await tester.pumpWidget(
        _app(
          DriverApplicationFormPage(
            api: _FakeDriverApplicationApi(),
            debugPickOne: (imageOnly) async {
              singlePickCount += 1;
              return DriverApplicationUploadFile(
                name: singlePickCount == 1 ? 'line.png' : 'line-new.png',
                bytes: const [1, 2, 3],
              );
            },
            debugPickVehiclePhotos: () async {
              vehiclePickCount += 1;
              return switch (vehiclePickCount) {
                1 => const [
                  DriverApplicationUploadFile(name: 'car1.jpg', bytes: [1]),
                ],
                2 => const [
                  DriverApplicationUploadFile(name: 'car2.jpg', bytes: [2]),
                ],
                3 => const [
                  DriverApplicationUploadFile(name: 'car3.jpg', bytes: [3]),
                ],
                4 => const [
                  DriverApplicationUploadFile(name: 'car4.jpg', bytes: [4]),
                  DriverApplicationUploadFile(name: 'car5.jpg', bytes: [5]),
                ],
                _ => const [
                  DriverApplicationUploadFile(name: 'car6.jpg', bytes: [6]),
                  DriverApplicationUploadFile(name: 'car7.jpg', bytes: [7]),
                ],
              };
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lineSelect = find.byKey(
        const ValueKey('driver_application_file_select_lineQr'),
      );
      await tester.scrollUntilVisible(
        lineSelect,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(lineSelect);
      await tester.pumpAndSettle();

      expect(find.text('line.png'), findsOneWidget);
      expect(lineSelect, findsNothing);
      expect(
        find.byKey(const ValueKey('driver_application_file_remove_lineQr')),
        findsOneWidget,
      );
      expect(find.textContaining('완료', skipOffstage: false), findsWidgets);
      expect(find.textContaining('교체', skipOffstage: false), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('driver_application_file_remove_lineQr')),
      );
      await tester.pumpAndSettle();
      expect(find.text('line.png'), findsNothing);
      expect(
        find.byKey(const ValueKey('driver_application_file_select_lineQr')),
        findsOneWidget,
      );

      final vehicleSelect = find.byKey(
        const ValueKey('driver_application_file_select_vehiclePhotos'),
      );
      await tester.tap(vehicleSelect);
      await tester.pumpAndSettle();
      expect(find.text('car1.jpg'), findsOneWidget);
      expect(find.textContaining('1/6', skipOffstage: false), findsWidgets);

      await tester.tap(vehicleSelect);
      await tester.pumpAndSettle();
      expect(find.text('car2.jpg'), findsOneWidget);
      expect(find.textContaining('2/6', skipOffstage: false), findsWidgets);

      await tester.tap(vehicleSelect);
      await tester.pumpAndSettle();
      expect(find.text('car3.jpg'), findsOneWidget);
      expect(find.textContaining('3/6', skipOffstage: false), findsWidgets);

      await tester.tap(vehicleSelect);
      await tester.pumpAndSettle();
      expect(find.text('car4.jpg'), findsOneWidget);
      expect(find.text('car5.jpg'), findsOneWidget);
      expect(find.textContaining('5/6', skipOffstage: false), findsWidgets);

      await tester.tap(vehicleSelect);
      await tester.pumpAndSettle();
      expect(find.text('car6.jpg'), findsOneWidget);
      expect(find.text('car7.jpg'), findsNothing);
      expect(find.textContaining('6/6', skipOffstage: false), findsWidgets);
      expect(vehicleSelect, findsNothing);
      expect(
        find.byKey(
          const ValueKey(
            'driver_application_file_select_disabled_vehiclePhotos',
          ),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('driver_application_file_remove_car2.jpg')),
      );
      await tester.pumpAndSettle();
      expect(find.text('car1.jpg'), findsOneWidget);
      expect(find.text('car2.jpg'), findsNothing);
      expect(find.text('car3.jpg'), findsOneWidget);
      expect(find.textContaining('5/6', skipOffstage: false), findsWidgets);
      expect(vehicleSelect, findsOneWidget);

      await tester.tap(vehicleSelect);
      await tester.pumpAndSettle();
      expect(find.text('car6.jpg'), findsOneWidget);
      expect(find.text('car7.jpg'), findsOneWidget);
      expect(find.textContaining('6/6', skipOffstage: false), findsWidgets);
    },
  );

  testWidgets('driver apply vehicle photos skip duplicate selections', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    var vehiclePickCount = 0;
    await tester.pumpWidget(
      _app(
        DriverApplicationFormPage(
          api: _FakeDriverApplicationApi(),
          debugPickVehiclePhotos: () async {
            vehiclePickCount += 1;
            return vehiclePickCount == 1
                ? const [
                    DriverApplicationUploadFile(name: 'car1.jpg', bytes: [1]),
                  ]
                : const [
                    DriverApplicationUploadFile(name: 'car1.jpg', bytes: [9]),
                    DriverApplicationUploadFile(name: 'car2.jpg', bytes: [2]),
                  ];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final vehicleSelect = find.byKey(
      const ValueKey('driver_application_file_select_vehiclePhotos'),
    );
    await tester.scrollUntilVisible(
      vehicleSelect,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(vehicleSelect);
    await tester.pumpAndSettle();
    await tester.tap(vehicleSelect);
    await tester.pumpAndSettle();

    expect(find.text('car1.jpg'), findsOneWidget);
    expect(find.text('car2.jpg'), findsOneWidget);
    expect(find.textContaining('중복', skipOffstage: false), findsWidgets);
    expect(find.textContaining('2/6', skipOffstage: false), findsWidgets);
  });

  testWidgets('driver apply upload card errors are scoped to the failed file', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      _app(
        DriverApplicationFormPage(
          api: _FakeDriverApplicationApi(),
          debugPickOne: (imageOnly) async {
            throw Exception('picker unavailable');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final lineSelect = find.byKey(
      const ValueKey('driver_application_file_select_lineQr'),
    );
    await tester.scrollUntilVisible(
      lineSelect,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(lineSelect);
    await tester.pumpAndSettle();

    final lineCard = find.byKey(
      const ValueKey('driver_application_file_card_lineQr'),
    );
    final insuranceCard = find.byKey(
      const ValueKey('driver_application_file_card_insuranceCertificate'),
    );
    expect(
      find.descendant(
        of: lineCard,
        matching: find.textContaining('다시 시도', skipOffstage: false),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: insuranceCard,
        matching: find.textContaining('다시 시도', skipOffstage: false),
      ),
      findsNothing,
    );
  });

  testWidgets('driver apply shows localized upload size error', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      _app(
        DriverApplicationFormPage(
          api: _UploadTooLargeDriverApplicationApi(),
          debugSubmitDraft: _draft(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final submit = find.byIcon(Icons.send_outlined);
    await tester.scrollUntilVisible(
      submit,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(find.textContaining('첨부 파일', skipOffstage: false), findsOneWidget);
    expect(
      find.textContaining('SyntaxError', skipOffstage: false),
      findsNothing,
    );
    expect(find.textContaining('<html>', skipOffstage: false), findsNothing);
  });

  testWidgets('driver apply shows backend vehicle year field error', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1000, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        DriverApplicationFormPage(
          api: _FieldErrorDriverApplicationApi(),
          debugSubmitDraft: _draft(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final submit = find.byIcon(Icons.send_outlined);
    await tester.scrollUntilVisible(
      submit,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(find.textContaining('2020', skipOffstage: false), findsWidgets);
  });

  testWidgets('driver apply password shorter than 6 chars shows red error', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      _app(DriverApplicationFormPage(api: _FakeDriverApplicationApi())),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(2), '1234');
    await tester.pump();

    expect(find.textContaining('6', skipOffstage: false), findsWidgets);
  });

  testWidgets('driver apply license expiry date picker fills YYYY-MM-DD', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      _app(DriverApplicationFormPage(api: _FakeDriverApplicationApi())),
    );
    await tester.pumpAndSettle();

    final picker = find.byIcon(Icons.calendar_today_outlined);
    await tester.scrollUntilVisible(
      picker,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text(_ymd(DateTime.now())), findsOneWidget);
  });

  testWidgets('driver apply license expiry keeps manual input', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      _app(DriverApplicationFormPage(api: _FakeDriverApplicationApi())),
    );
    await tester.pumpAndSettle();

    final field = await _visibleLicenseExpiryField(tester);
    await tester.enterText(field, '2030-01-01');
    await tester.pump();

    expect(find.text('2030-01-01'), findsWidgets);
  });

  testWidgets('driver apply license expiry rejects past dates', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1000, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(DriverApplicationFormPage(api: _FakeDriverApplicationApi())),
    );
    await tester.pumpAndSettle();

    final field = await _visibleLicenseExpiryField(tester);
    await tester.enterText(field, '2000-01-01');
    await tester.pump();

    final submit = find.byIcon(Icons.send_outlined);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(find.textContaining('2000-01-01'), findsWidgets);
    expect(find.textContaining('6', skipOffstage: false), findsWidgets);
  });

  testWidgets('driver apply missing documents block submit', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = _FakeDriverApplicationApi();
    await tester.pumpWidget(_app(DriverApplicationFormPage(api: api)));
    await tester.pumpAndSettle();

    final submit = find.byIcon(Icons.send_outlined);
    await tester.scrollUntilVisible(
      submit,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(api.submitCalls, 0);
    expect(find.textContaining('3', skipOffstage: false), findsWidgets);
  });

  testWidgets('driver apply page has no overflow on small screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _app(DriverApplicationFormPage(api: _FakeDriverApplicationApi())),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(TextFormField), findsWidgets);
  });
  testWidgets('driver application status route is not exposed from login', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'driver_application_number': 'DA260703A1B2C3D4',
      'driver_application_status_token': 'raw-token',
    });
    await tester.pumpWidget(_app(const DriverLoginPage(api: _FakeDriverApi())));
    await tester.pumpAndSettle();

    expect(find.text('기사 등록 신청 / สมัครคนขับ'), findsOneWidget);
    expect(find.text('Check saved application status'), findsNothing);
    expect(find.text('Edit and resubmit'), findsNothing);
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

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tride_driver/config/app_config.dart';
import 'package:tride_driver/config/app_environment.dart';
import 'package:tride_driver/core/network/api_client.dart';
import 'package:tride_driver/features/driver_application/data/driver_application_api.dart';
import 'package:tride_driver/features/driver_application/data/driver_application_models.dart';
import 'package:tride_driver/features/driver_application/presentation/driver_application_complete_page.dart';
import 'package:tride_driver/features/driver_application/presentation/driver_application_form_page.dart';

import 'l10n_test_helpers.dart';
import 'test_fakes.dart';

void main() {
  DriverApplicationApi api(http.Client client) => DriverApplicationApi(
    client: ApiClient(
      config: AppConfig.forEnvironment(AppEnvironment.stg),
      httpClient: client,
    ),
  );

  Map<String, dynamic> envelope(Object data) => {'success': true, 'data': data};

  DriverApplicationUploadFile file(String name, {List<int> bytes = const [1]}) {
    return DriverApplicationUploadFile(filename: name, bytes: bytes);
  }

  DriverApplicationDraft validDraft({
    List<DriverApplicationUploadFile>? vehiclePhotos,
  }) {
    return DriverApplicationDraft(
      fullName: 'Somchai Driver',
      password: 'secret1',
      passwordConfirm: 'secret1',
      phone: '0812345678',
      phoneCountryCode: '+66',
      countryCode: 'TH',
      locale: 'ko',
      drivingLicenseNumber: 'L-123456',
      drivingLicenseCountry: 'TH',
      yearsOfDrivingExperience: 1,
      vehicleOwnershipType: 'OWNED',
      vehicleTypeCode: 'SEDAN',
      vehiclePlateNumber: 'ABC 1234',
      serviceAreas: const ['Bangkok'],
      languages: const ['ko'],
      files: DriverApplicationFileBundle(
        lineQr: file('line.png'),
        vehiclePhotos: vehiclePhotos ??
            [
              file('car1.jpg'),
              file('car2.jpg'),
              file('car3.jpg'),
            ],
        insuranceCertificate: file('insurance.pdf'),
        vehicleRegistration: file('registration.pdf'),
        taxCertificate: file('tax.pdf'),
      ),
      personalDataConsent: true,
      driverTermsConsent: true,
    );
  }

  group('DriverApplicationFormValidator', () {
    test('flags missing required fields', () {
      final issues = DriverApplicationFormValidator.validate(
        validDraft().copyWithPlaceholder(
          fullName: '',
          phone: '',
          drivingLicenseNumber: '',
          vehiclePlateNumber: '',
        ),
      );
      expect(issues, contains(DriverApplicationValidationIssue.requiredField));
    });

    test('flags password mismatch', () {
      final issues = DriverApplicationFormValidator.validate(
        validDraft().copyWithPlaceholder(passwordConfirm: 'other'),
      );
      expect(
        issues,
        contains(DriverApplicationValidationIssue.passwordMismatch),
      );
    });

    test('flags short password', () {
      final issues = DriverApplicationFormValidator.validate(
        validDraft().copyWithPlaceholder(password: '123', passwordConfirm: '123'),
      );
      expect(
        issues,
        contains(DriverApplicationValidationIssue.passwordTooShort),
      );
    });

    test('flags vehicle photo count below minimum', () {
      final issues = DriverApplicationFormValidator.validate(
        validDraft(
          vehiclePhotos: [
            file('one.jpg'),
            file('two.jpg'),
          ],
        ),
      );
      expect(
        issues,
        contains(DriverApplicationValidationIssue.vehiclePhotoCount),
      );
    });

    test('flags vehicle photo count above maximum', () {
      final issues = DriverApplicationFormValidator.validate(
        validDraft(
          vehiclePhotos: List.generate(
            7,
            (index) => file('photo$index.jpg'),
          ),
        ),
      );
      expect(
        issues,
        contains(DriverApplicationValidationIssue.vehiclePhotoCount),
      );
    });

    test('flags missing consent and files', () {
      final draft = validDraft().copyWithPlaceholder(
        personalDataConsent: false,
        driverTermsConsent: false,
        files: const DriverApplicationFileBundle(),
      );
      expect(
        DriverApplicationFormValidator.validate(draft),
        containsAll([
          DriverApplicationValidationIssue.consentMissing,
          DriverApplicationValidationIssue.missingFile,
          DriverApplicationValidationIssue.vehiclePhotoCount,
        ]),
      );
    });
  });

  group('DriverApplicationDraft multipart', () {
    test('uses exact field names and comma-separated lists', () {
      final draft = validDraft();
      final fields = draft.toMultipartFields();
      expect(fields['fullName'], 'Somchai Driver');
      expect(fields['passwordConfirm'], 'secret1');
      expect(fields['phoneCountryCode'], '+66');
      expect(fields['countryCode'], 'TH');
      expect(fields['locale'], 'ko');
      expect(fields['yearsOfDrivingExperience'], '1');
      expect(fields['vehicleOwnershipType'], 'OWNED');
      expect(fields['vehicleTypeCode'], 'SEDAN');
      expect(fields['serviceAreas'], 'Bangkok');
      expect(fields['languages'], 'ko');
      expect(fields['personalDataConsent'], 'true');
      expect(fields['driverTermsConsent'], 'true');

      final multipartFiles = draft.toMultipartFiles();
      expect(
        multipartFiles.map((item) => item.field),
        [
          'lineQr',
          'vehiclePhotos',
          'vehiclePhotos',
          'vehiclePhotos',
          'insuranceCertificate',
          'vehicleRegistration',
          'taxCertificate',
        ],
      );
    });
  });

  group('DriverApplicationApi', () {
    test('vehicle types GET is public and parses response', () async {
      late http.Request request;
      final types = await api(
        MockClient((incoming) async {
          request = incoming;
          return http.Response(
            jsonEncode(
              envelope([
                {'id': 1, 'code': 'SEDAN', 'name': 'Sedan'},
              ]),
            ),
            200,
          );
        }),
      ).listVehicleTypes();

      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/vehicles/types');
      expect(request.headers.containsKey('authorization'), isFalse);
      expect(types.single.code, 'SEDAN');
    });

    test('submit rejects invalid draft before transport', () async {
      var calls = 0;
      await expectLater(
        api(
          MockClient((_) async {
            calls++;
            return http.Response('{}', 500);
          }),
        ).submitApplication(
          validDraft().copyWithPlaceholder(passwordConfirm: 'mismatch'),
        ),
        throwsA(
          isA<DriverApplicationApiException>().having(
            (error) => error.kind,
            'kind',
            DriverApplicationFailureKind.validation,
          ),
        ),
      );
      expect(calls, 0);
    });

    test('submit success parses receipt without bearer token', () async {
      late http.Request request;
      final receipt = await api(
        MockClient((incoming) async {
          request = incoming;
          return http.Response(
            jsonEncode(
              envelope({
                'applicationNumber': 'DA-2026-0001',
                'status': 'PENDING',
                'statusToken': 'secret-token',
                'submittedAt': '2026-07-28T00:00:00.000Z',
              }),
            ),
            201,
          );
        }),
      ).submitApplication(validDraft());

      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/driver-applications');
      expect(request.headers.containsKey('authorization'), isFalse);
      expect(receipt.applicationNumber, 'DA-2026-0001');
      expect(receipt.statusToken, 'secret-token');
    });

    test('submit multipart field names match backend contract', () async {
      late http.Request request;
      await api(
        MockClient((incoming) async {
          request = incoming;
          return http.Response(
            jsonEncode(
              envelope({
                'applicationNumber': 'DA-1',
                'status': 'PENDING',
                'statusToken': 't',
                'submittedAt': '2026-07-28',
              }),
            ),
            201,
          );
        }),
      ).submitApplication(validDraft());

      final body = request.body;
      for (final field in [
        'fullName',
        'password',
        'passwordConfirm',
        'phone',
        'vehicleTypeCode',
        'serviceAreas',
        'personalDataConsent',
        'driverTermsConsent',
      ]) {
        expect(body, contains('name="$field"'));
      }
      expect('name="vehiclePhotos"'.allMatches(body), hasLength(3));
      expect('name="lineQr"'.allMatches(body), hasLength(1));
      expect('name="insuranceCertificate"'.allMatches(body), hasLength(1));
      expect('name="vehicleRegistration"'.allMatches(body), hasLength(1));
      expect('name="taxCertificate"'.allMatches(body), hasLength(1));
    });

    test('submit classifies phone conflict', () async {
      await expectLater(
        api(
          MockClient(
            (_) async => http.Response(
              jsonEncode({
                'success': false,
                'error_code': 'CONFLICT',
                'errors': [
                  {'field': 'phone', 'message': 'duplicate'},
                ],
              }),
              409,
            ),
          ),
        ).submitApplication(validDraft()),
        throwsA(
          isA<DriverApplicationApiException>().having(
            (error) => error.kind,
            'kind',
            DriverApplicationFailureKind.phoneConflict,
          ),
        ),
      );
    });

    test('submit classifies plate conflict', () async {
      await expectLater(
        api(
          MockClient(
            (_) async => http.Response(
              jsonEncode({
                'success': false,
                'error_code': 'CONFLICT',
                'errors': [
                  {'field': 'vehiclePlateNumber', 'message': 'duplicate'},
                ],
              }),
              409,
            ),
          ),
        ).submitApplication(validDraft()),
        throwsA(
          isA<DriverApplicationApiException>().having(
            (error) => error.kind,
            'kind',
            DriverApplicationFailureKind.plateConflict,
          ),
        ),
      );
    });
  });

  group('DriverApplicationFormPage', () {
    Future<void> enterField(
      WidgetTester tester,
      Key key,
      String value,
    ) async {
      final finder = find.byKey(key);
      await tester.ensureVisible(finder);
      await tester.enterText(finder, value);
    }

    Future<void> tapField(WidgetTester tester, Key key) async {
      final finder = find.byKey(key);
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> tapSelectButton(WidgetTester tester, Key selectorKey) async {
      final button = find.descendant(
        of: find.byKey(selectorKey),
        matching: find.text('선택'),
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets('shows validation snackbar for password mismatch', (
      tester,
    ) async {
      _useTallView(tester);
      final fakeApi = _FakeDriverApplicationApi();
      await pumpLocalizedWidget(
        tester,
        home: DriverApplicationFormPage(
          api: fakeApi,
          pickPhotos: (_) async => List.generate(
            3,
            (index) => file('photo$index.jpg'),
          ),
          pickDocument: ({required bool imageOnly}) async =>
              file(imageOnly ? 'line.png' : 'doc.pdf'),
        ),
      );

      await enterField(tester, const Key('driverApplyFullName'), 'Driver Name');
      await enterField(tester, const Key('driverApplyPhone'), '0812345678');
      await enterField(tester, const Key('driverApplyPassword'), 'secret1');
      await enterField(
        tester,
        const Key('driverApplyPasswordConfirm'),
        'other',
      );
      await enterField(tester, const Key('driverApplyLicenseNumber'), 'L-1');
      await enterField(tester, const Key('driverApplyVehiclePlate'), 'ABC 1');
      await enterField(tester, const Key('driverApplyServiceAreas'), 'Bangkok');

      await tapSelectButton(tester, const Key('driverApplyLineQr'));
      await tapField(tester, const Key('driverApplyVehiclePhotos'));
      await tapSelectButton(tester, const Key('driverApplyInsurance'));
      await tapSelectButton(tester, const Key('driverApplyRegistration'));
      await tapSelectButton(tester, const Key('driverApplyTaxCertificate'));
      await tapField(tester, const Key('driverApplyPersonalConsent'));
      await tapField(tester, const Key('driverApplyTermsConsent'));

      await tapField(tester, const Key('driverApplySubmit'));

      expect(find.text('비밀번호가 일치하지 않습니다.'), findsOneWidget);
      expect(fakeApi.submitCount, 0);
    });

    testWidgets('invokes onSubmitted with receipt', (tester) async {
      _useTallView(tester);
      final fakeApi = _FakeDriverApplicationApi();
      DriverApplicationReceipt? captured;
      await pumpLocalizedWidget(
        tester,
        home: DriverApplicationFormPage(
          api: fakeApi,
          onSubmitted: (receipt) => captured = receipt,
          pickPhotos: (_) async => List.generate(
            3,
            (index) => file('photo$index.jpg'),
          ),
          pickDocument: ({required bool imageOnly}) async =>
              file(imageOnly ? 'line.png' : 'doc.pdf'),
        ),
      );

      await _fillValidForm(tester);
      await tapField(tester, const Key('driverApplySubmit'));

      expect(fakeApi.submitCount, 1);
      expect(captured?.applicationNumber, 'DA-TEST-1');
    });

    testWidgets('successful submit navigates to complete page and stores info', (
      tester,
    ) async {
      _useTallView(tester);
      final fakeApi = _FakeDriverApplicationApi();
      final storage = FakeTokenStorage();
      await pumpLocalizedWidget(
        tester,
        home: DriverApplicationFormPage(
          api: fakeApi,
          tokenStorage: storage,
          pickPhotos: (_) async => List.generate(
            3,
            (index) => file('photo$index.jpg'),
          ),
          pickDocument: ({required bool imageOnly}) async =>
              file(imageOnly ? 'line.png' : 'doc.pdf'),
        ),
      );

      await _fillValidForm(tester);
      await tapField(tester, const Key('driverApplySubmit'));

      expect(find.byKey(const Key('driverApplicationCompleteNumber')), findsOneWidget);
      expect(find.textContaining('DA-TEST-1'), findsOneWidget);
      expect(find.text('관리자에게 승인 요청 했습니다.'), findsOneWidget);
      expect(find.byKey(const Key('driverApplicationLineQr')), findsOneWidget);
      expect(storage.driverApplicationWriteCount, greaterThan(0));
      final saved = await storage.readDriverApplicationInfo();
      expect(saved?.applicationNumber, 'DA-TEST-1');
      expect(saved?.statusToken, 'token');
    });
  });

  group('DriverApplicationCompletePage', () {
    testWidgets('renders application number, guidance, and QR image', (
      tester,
    ) async {
      _useTallView(tester);
      await pumpLocalizedWidget(
        tester,
        home: const DriverApplicationCompletePage(
          receipt: DriverApplicationReceipt(
            applicationNumber: 'DA-2026-0001',
            status: 'PENDING',
            statusToken: 'secret-token',
            submittedAt: '2026-07-28T00:00:00.000Z',
          ),
        ),
      );

      expect(
        find.byKey(const Key('driverApplicationSubmittedMessage')),
        findsOneWidget,
      );
      expect(find.text('관리자에게 승인 요청 했습니다.'), findsOneWidget);
      expect(
        find.byKey(const Key('driverApplicationLineGroupInstruction')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('driverApplicationCompleteNumber')),
        findsOneWidget,
      );
      expect(find.textContaining('DA-2026-0001'), findsOneWidget);
      expect(
        find.byKey(const Key('driverApplicationNumberStatusHint')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('driverApplicationLineQr')), findsOneWidget);
      expect(find.byKey(const Key('driverApplicationBackToLogin')), findsOneWidget);
    });

    testWidgets('persists receipt through secure storage on entry', (
      tester,
    ) async {
      _useTallView(tester);
      final storage = FakeTokenStorage();
      await pumpLocalizedWidget(
        tester,
        home: DriverApplicationCompletePage(
          tokenStorage: storage,
          receipt: const DriverApplicationReceipt(
            applicationNumber: 'DA-STORE-1',
            status: 'PENDING',
            statusToken: 'stored-token',
            submittedAt: '2026-07-29',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(storage.driverApplicationWriteCount, 1);
      final saved = await storage.readDriverApplicationInfo();
      expect(saved?.applicationNumber, 'DA-STORE-1');
      expect(saved?.statusToken, 'stored-token');
    });
  });
}

Future<void> _fillValidForm(WidgetTester tester) async {
  Future<void> enter(Key key, String value) async {
    final finder = find.byKey(key);
    await tester.ensureVisible(finder);
    await tester.enterText(finder, value);
  }

  Future<void> tap(Key key) async {
    final finder = find.byKey(key);
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> tapSelect(Key selectorKey) async {
    final button = find.descendant(
      of: find.byKey(selectorKey),
      matching: find.text('선택'),
    );
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  await enter(const Key('driverApplyFullName'), 'Driver Name');
  await enter(const Key('driverApplyPhone'), '0812345678');
  await enter(const Key('driverApplyPassword'), 'secret1');
  await enter(const Key('driverApplyPasswordConfirm'), 'secret1');
  await enter(const Key('driverApplyLicenseNumber'), 'L-1');
  await enter(const Key('driverApplyVehiclePlate'), 'ABC 1');
  await enter(const Key('driverApplyServiceAreas'), 'Bangkok');

  await tapSelect(const Key('driverApplyLineQr'));
  await tap(const Key('driverApplyVehiclePhotos'));
  await tapSelect(const Key('driverApplyInsurance'));
  await tapSelect(const Key('driverApplyRegistration'));
  await tapSelect(const Key('driverApplyTaxCertificate'));
  await tap(const Key('driverApplyPersonalConsent'));
  await tap(const Key('driverApplyTermsConsent'));
}

void _useTallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

class _FakeDriverApplicationApi implements DriverApplicationDataSource {
  int submitCount = 0;

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
    submitCount++;
    return const DriverApplicationReceipt(
      applicationNumber: 'DA-TEST-1',
      status: 'PENDING',
      statusToken: 'token',
      submittedAt: '2026-07-28',
    );
  }
}

extension on DriverApplicationDraft {
  DriverApplicationDraft copyWithPlaceholder({
    String? fullName,
    String? password,
    String? passwordConfirm,
    String? phone,
    String? drivingLicenseNumber,
    String? vehiclePlateNumber,
    bool? personalDataConsent,
    bool? driverTermsConsent,
    DriverApplicationFileBundle? files,
  }) {
    return DriverApplicationDraft(
      fullName: fullName ?? this.fullName,
      password: password ?? this.password,
      passwordConfirm: passwordConfirm ?? this.passwordConfirm,
      phone: phone ?? this.phone,
      phoneCountryCode: phoneCountryCode,
      countryCode: countryCode,
      locale: locale,
      drivingLicenseNumber: drivingLicenseNumber ?? this.drivingLicenseNumber,
      drivingLicenseCountry: drivingLicenseCountry,
      drivingLicenseExpiryDate: drivingLicenseExpiryDate,
      yearsOfDrivingExperience: yearsOfDrivingExperience,
      vehicleOwnershipType: vehicleOwnershipType,
      vehicleTypeCode: vehicleTypeCode,
      vehicleMake: vehicleMake,
      vehicleModel: vehicleModel,
      vehicleYear: vehicleYear,
      vehicleColor: vehicleColor,
      vehiclePlateNumber: vehiclePlateNumber ?? this.vehiclePlateNumber,
      serviceAreas: serviceAreas,
      languages: languages,
      files: files ?? this.files,
      personalDataConsent: personalDataConsent ?? this.personalDataConsent,
      driverTermsConsent: driverTermsConsent ?? this.driverTermsConsent,
    );
  }
}

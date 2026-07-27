import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tride_driver/config/app_config.dart';
import 'package:tride_driver/config/app_environment.dart';
import 'package:tride_driver/core/network/api_client.dart';
import 'package:tride_driver/core/network/api_exception.dart';
import 'package:tride_driver/core/storage/secure_token_storage.dart';
import 'package:tride_driver/features/account/data/account_api.dart';
import 'package:tride_driver/features/account/data/account_models.dart';

import 'test_fakes.dart';

void main() {
  AccountApi api(http.Client client) => AccountApi(
    client: ApiClient(
      config: AppConfig.forEnvironment(AppEnvironment.stg),
      httpClient: client,
    ),
    storage: FakeTokenStorage(
      const AuthTokens(accessToken: 'account-token', refreshToken: 'refresh'),
    ),
  );

  Map<String, dynamic> envelope(Object data) => {'success': true, 'data': data};

  final profileData = {
    'name': 'Somchai',
    'phone': '+66812345678',
    'email': 'driver@example.com',
    'avatarUrl': '/api/v1/driver/profile/avatar',
    'vehicle': {
      'typeCode': 'SEDAN',
      'typeName': 'Sedan',
      'modelName': 'Camry',
      'plateNumber': 'ABC 1234',
      'color': 'White',
      'year': 2022,
      'photoUrl': null,
    },
  };

  test('profile GET parses the complete contract', () async {
    late http.Request request;
    final result = await api(
      MockClient((incoming) async {
        request = incoming;
        return http.Response(jsonEncode(envelope(profileData)), 200);
      }),
    ).getProfile();

    expect(request.method, 'GET');
    expect(request.url.path, '/api/v1/driver/profile');
    expect(request.headers['authorization'], 'Bearer account-token');
    expect(result.name, 'Somchai');
    expect(result.vehicle?.year, 2022);
    expect(result.avatarUrl, '/api/v1/driver/profile/avatar');
  });

  test('protected profile image GET includes the bearer token', () async {
    late http.Request request;
    final bytes = await api(
      MockClient((incoming) async {
        request = incoming;
        return http.Response.bytes(const [1, 2, 3], 200);
      }),
    ).loadAsset('/api/v1/driver/profile/vehicle-photo');

    expect(request.method, 'GET');
    expect(request.url.path, '/api/v1/driver/profile/vehicle-photo');
    expect(request.headers['authorization'], 'Bearer account-token');
    expect(bytes, [1, 2, 3]);
  });

  test('profile PATCH sends only supplied changes', () async {
    late http.Request request;
    await api(
      MockClient((incoming) async {
        request = incoming;
        return http.Response(
          jsonEncode(envelope({...profileData, 'phone': '+66800000000'})),
          200,
        );
      }),
    ).updateProfile({'phone': '+66800000000'});

    expect(request.method, 'PATCH');
    expect(jsonDecode(request.body), {'phone': '+66800000000'});
  });

  test('profile PATCH rejects empty changes before transport', () async {
    var calls = 0;
    await expectLater(
      api(
        MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      ).updateProfile(const {}),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.validation,
        ),
      ),
    );
    expect(calls, 0);
  });

  test('profile GET classifies server failure', () async {
    await expectLater(
      api(
        MockClient(
          (_) async => http.Response(
            '{"success":false,"error_code":"INTERNAL_SERVER_ERROR"}',
            500,
          ),
        ),
      ).getProfile(),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.server,
        ),
      ),
    );
  });

  test('profile PATCH classifies backend validation failure', () async {
    await expectLater(
      api(
        MockClient(
          (_) async => http.Response(
            '{"success":false,"error_code":"VALIDATION_ERROR"}',
            400,
          ),
        ),
      ).updateProfile({'phone': 'bad'}),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.validation,
        ),
      ),
    );
  });

  for (final endpoint in [
    '/api/v1/driver/profile/avatar',
    '/api/v1/driver/profile/vehicle-photo',
  ]) {
    test('$endpoint uploads exactly one file field', () async {
      late http.Request request;
      final account = api(
        MockClient((incoming) async {
          request = incoming;
          return http.Response(jsonEncode(envelope({'fileId': 1})), 200);
        }),
      );
      const file = AccountUploadFile(filename: 'photo.jpg', bytes: [1, 2, 3]);

      if (endpoint.endsWith('avatar')) {
        await account.uploadAvatar(file);
      } else {
        await account.uploadVehiclePhoto(file);
      }

      expect(request.method, 'POST');
      expect(request.url.path, endpoint);
      expect(request.body, contains('name="file"'));
      expect(request.body, contains('filename="photo.jpg"'));
    });
  }

  test('upload classifies FILE_TOO_LARGE', () async {
    await expectLater(
      api(
        MockClient(
          (_) async => http.Response(
            '{"success":false,"error_code":"FILE_TOO_LARGE"}',
            400,
          ),
        ),
      ).uploadAvatar(
        const AccountUploadFile(filename: 'photo.jpg', bytes: [1]),
      ),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.fileTooLarge,
        ),
      ),
    );
  });

  test('vehicle photo upload classifies backend validation conflict', () async {
    await expectLater(
      api(
        MockClient(
          (_) async => http.Response(
            '{"success":false,"error_code":"VALIDATION_ERROR"}',
            409,
          ),
        ),
      ).uploadVehiclePhoto(
        const AccountUploadFile(filename: 'vehicle.jpg', bytes: [1]),
      ),
      throwsA(
        isA<ApiException>()
            .having((error) => error.kind, 'kind', ApiFailureKind.validation)
            .having((error) => error.statusCode, 'statusCode', 409),
      ),
    );
  });

  test('vehicles GET parses status and document counts', () async {
    final result = await api(
      MockClient(
        (_) async => http.Response(
          jsonEncode(
            envelope({
              'items': [
                {
                  'id': 11,
                  'vehicleTypeId': 2,
                  'vehicleTypeCode': 'SUV',
                  'vehicleTypeName': 'SUV',
                  'plateNumber': 'ABC-123',
                  'modelName': null,
                  'color': 'Black',
                  'isPrimary': false,
                  'isActive': false,
                  'approvalStatus': 'PENDING',
                  'rejectionReason': null,
                  'documentCounts': {
                    'vehiclePhotos': 3,
                    'insuranceCertificate': 1,
                    'vehicleRegistration': 1,
                    'taxCertificate': 0,
                  },
                },
              ],
            }),
          ),
          200,
        ),
      ),
    ).getVehicles();

    expect(result.single.approvalStatus, 'PENDING');
    expect(result.single.documentCounts.vehiclePhotos, 3);
  });

  test('vehicles GET classifies authentication failure', () async {
    await expectLater(
      api(
        MockClient(
          (_) async => http.Response(
            '{"success":false,"error_code":"UNAUTHORIZED"}',
            401,
          ),
        ),
      ).getVehicles(),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.unauthorized,
        ),
      ),
    );
  });

  test('vehicle POST uses exact fields and no tax certificate', () async {
    late http.Request request;
    final created = await api(
      MockClient((incoming) async {
        request = incoming;
        return http.Response(
          jsonEncode(
            envelope({
              'id': 99,
              'vehicleTypeId': 2,
              'vehicleTypeCode': 'SUV',
              'vehicleTypeName': 'SUV',
              'plateNumber': 'NEW-999',
              'modelName': 'X',
              'color': 'Red',
              'isPrimary': false,
              'isActive': false,
              'approvalStatus': 'PENDING',
              'rejectionReason': null,
              'documentCounts': {
                'vehiclePhotos': 3,
                'insuranceCertificate': 1,
                'vehicleRegistration': 1,
                'taxCertificate': 0,
              },
            }),
          ),
          201,
        );
      }),
    ).createVehicle(_validRequest());

    expect(created.approvalStatus, 'PENDING');
    expect(request.body, contains('name="vehicleTypeId"'));
    expect(request.body, contains('name="plateNumber"'));
    expect('name="vehiclePhotos"'.allMatches(request.body), hasLength(3));
    expect(
      'name="insuranceCertificate"'.allMatches(request.body),
      hasLength(1),
    );
    expect('name="vehicleRegistration"'.allMatches(request.body), hasLength(1));
    expect(request.body, isNot(contains('taxCertificate')));
  });

  test('vehicle POST rejects invalid photo count before transport', () async {
    var calls = 0;
    await expectLater(
      api(
        MockClient((_) async {
          calls++;
          return http.Response('{}', 500);
        }),
      ).createVehicle(
        VehicleCreateRequest(
          vehicleTypeId: 1,
          plateNumber: 'AB-12',
          vehiclePhotos: const [
            AccountUploadFile(filename: 'one.jpg', bytes: [1]),
            AccountUploadFile(filename: 'two.jpg', bytes: [2]),
          ],
          insuranceCertificate: const AccountUploadFile(
            filename: 'insurance.pdf',
            bytes: [1],
          ),
          vehicleRegistration: const AccountUploadFile(
            filename: 'registration.pdf',
            bytes: [1],
          ),
        ),
      ),
      throwsA(isA<ApiException>()),
    );
    expect(calls, 0);
  });

  test('vehicle POST classifies duplicate plate', () async {
    await expectLater(
      api(
        MockClient(
          (_) async => http.Response(
            '{"success":false,"error_code":"VEHICLE_PLATE_ALREADY_REGISTERED"}',
            409,
          ),
        ),
      ).createVehicle(_validRequest()),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.vehiclePlateAlreadyRegistered,
        ),
      ),
    );
  });

  test('rating summary parses rating and no-review null', () async {
    final account = api(
      MockClient(
        (_) async => http.Response(
          jsonEncode(envelope({'averageRating': null, 'reviewCount': 0})),
          200,
        ),
      ),
    );
    final result = await account.getRatingSummary();
    expect(result.averageRating, isNull);
    expect(result.reviewCount, 0);
  });

  test('account GET failure preserves unauthorized classification', () async {
    await expectLater(
      api(
        MockClient(
          (_) async => http.Response(
            '{"success":false,"error_code":"UNAUTHORIZED"}',
            401,
          ),
        ),
      ).getRatingSummary(),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.unauthorized,
        ),
      ),
    );
  });
}

VehicleCreateRequest _validRequest() => VehicleCreateRequest(
  vehicleTypeId: 2,
  plateNumber: 'NEW-999',
  modelName: 'X',
  color: 'Red',
  vehiclePhotos: const [
    AccountUploadFile(filename: 'one.jpg', bytes: [1]),
    AccountUploadFile(filename: 'two.png', bytes: [2]),
    AccountUploadFile(filename: 'three.webp', bytes: [3]),
  ],
  insuranceCertificate: const AccountUploadFile(
    filename: 'insurance.pdf',
    bytes: [1],
  ),
  vehicleRegistration: const AccountUploadFile(
    filename: 'registration.pdf',
    bytes: [1],
  ),
);

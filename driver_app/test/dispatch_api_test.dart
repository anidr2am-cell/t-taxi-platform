import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tride_driver/config/app_config.dart';
import 'package:tride_driver/config/app_environment.dart';
import 'package:tride_driver/core/network/api_client.dart';
import 'package:tride_driver/core/network/api_exception.dart';
import 'package:tride_driver/core/storage/secure_token_storage.dart';
import 'package:tride_driver/features/dispatch/data/dispatch_api.dart';
import 'package:tride_driver/features/dispatch/data/dispatch_repository.dart';

import 'test_fakes.dart';

void main() {
  ApiClient client(http.Client httpClient) => ApiClient(
    config: AppConfig.forEnvironment(AppEnvironment.stg),
    httpClient: httpClient,
  );

  FakeTokenStorage storage() => FakeTokenStorage(
    const AuthTokens(accessToken: 'dispatch-token', refreshToken: 'refresh'),
  );

  Map<String, dynamic> statusEnvelope({required bool online}) => {
    'success': true,
    'data': {
      'driverId': 7,
      'active': true,
      'online': online,
      'status': online ? 'AVAILABLE' : 'OFFLINE',
      'hasActiveJob': false,
      'lastSeenAt': '2026-07-27T01:00:00.000Z',
      'callEligibility': {
        'canReceiveCalls': online,
        'reasonCode': online ? 'READY' : 'OFFLINE',
      },
    },
  };

  for (final scenario in [
    ('status', 'GET', '/api/v1/driver/status', false),
    ('online', 'POST', '/api/v1/driver/online', true),
    ('offline', 'POST', '/api/v1/driver/offline', false),
  ]) {
    test('${scenario.$1} uses ${scenario.$2} and parses status', () async {
      late http.Request request;
      final repository = DispatchRepository(
        DispatchApi(
          client: client(
            MockClient((incoming) async {
              request = incoming;
              return http.Response(
                jsonEncode(statusEnvelope(online: scenario.$4)),
                200,
              );
            }),
          ),
          storage: storage(),
        ),
      );

      final result = switch (scenario.$1) {
        'online' => await repository.goOnline(),
        'offline' => await repository.goOffline(),
        _ => await repository.getStatus(),
      };

      expect(request.method, scenario.$2);
      expect(request.url.path, scenario.$3);
      expect(request.headers['authorization'], 'Bearer dispatch-token');
      expect(result.online, scenario.$4);
      expect(
        result.callEligibility.reasonCode,
        scenario.$4 ? 'READY' : 'OFFLINE',
      );
    });
  }

  test('open calls parses exact backend vehicle contract', () async {
    final repository = DispatchRepository(
      DispatchApi(
        client: client(
          MockClient(
            (_) async => http.Response(
              jsonEncode({
                'success': true,
                'data': {
                  'items': [
                    {
                      'bookingNumber': 'TX209912319998',
                      'status': 'OPEN',
                      'scheduledPickupAt': '2026-07-27T10:30:00+07:00',
                      'pickupDate': '2026-07-27',
                      'pickupTime': '10:30',
                      'origin': 'BKK',
                      'destination': 'Pattaya Hotel',
                      'serviceType': {
                        'code': 'AIRPORT_PICKUP',
                        'name': 'Airport pickup',
                      },
                      'vehicleType': {'code': 'SEDAN', 'name': 'Sedan'},
                      'vehicleMatchType': 'COMPATIBLE_UPGRADE',
                      'isExactVehicleMatch': false,
                      'compatibleVehicles': [
                        {
                          'driverVehicleId': 22,
                          'vehicleTypeCode': 'VAN',
                          'vehicleTypeName': 'Van',
                          'plateNumber': 'V-22',
                          'isExactMatch': false,
                        },
                      ],
                      'passengerCount': 2,
                      'amount': 1200,
                      'currency': 'THB',
                      'customerPaymentAmount': 1200,
                      'customerPaymentCurrency': 'THB',
                      'customerPaymentMethod': 'PAY_DRIVER',
                      'companyCommissionAmount': 300,
                      'companyCommissionCurrency': 'THB',
                      'driverExpectedIncomeAmount': 900,
                      'driverExpectedIncomeCurrency': 'THB',
                      'luggage': {
                        'carriers20Inch': 1,
                        'carriers24InchPlus': 0,
                        'golfBags': 0,
                        'specialItems': null,
                      },
                      'isUrgentRequest': false,
                      'negotiationId': null,
                      'minRequiredEtaMinutes': null,
                    },
                  ],
                },
              }),
              200,
            ),
          ),
        ),
        storage: storage(),
      ),
    );

    final result = await repository.getOpenCalls();

    expect(result.items.single.origin, 'BKK');
    expect(result.items.single.destination, 'Pattaya Hotel');
    expect(result.items.single.vehicleMatchType, 'COMPATIBLE_UPGRADE');
    expect(result.items.single.isExactVehicleMatch, isFalse);
    expect(result.items.single.compatibleVehicles.single.driverVehicleId, 22);
    expect(result.items.single.compatibleVehicles.single.plateNumber, 'V-22');
    expect(result.items.single.driverExpectedIncomeAmount, 900);
    expect(result.items.single.luggage.carriers20Inch, 1);
  });

  test('claim posts driverVehicleId and parses assigned booking', () async {
    late http.Request request;
    final repository = DispatchRepository(
      DispatchApi(
        client: client(
          MockClient((incoming) async {
            request = incoming;
            return http.Response(
              jsonEncode({
                'success': true,
                'data': {
                  'bookingNumber': 'TX209912319998',
                  'status': 'DRIVER_ASSIGNED',
                  'booking': {
                    'bookingNumber': 'TX209912319998',
                    'status': 'DRIVER_ASSIGNED',
                  },
                },
              }),
              200,
            );
          }),
        ),
        storage: storage(),
      ),
    );

    final result = await repository.claimOpenCall('TX209912319998', 22);

    expect(request.method, 'POST');
    expect(request.url.path, '/api/v1/driver/calls/TX209912319998/claim');
    expect(jsonDecode(request.body), {'driverVehicleId': 22});
    expect(result.status, 'DRIVER_ASSIGNED');
  });

  for (final scenario in [
    ('DRIVER_BOOKING_TIME_CONFLICT', ApiFailureKind.bookingTimeConflict),
    ('ALREADY_ASSIGNED', ApiFailureKind.alreadyClaimed),
  ]) {
    test('claim classifies ${scenario.$1}', () async {
      final repository = DispatchRepository(
        DispatchApi(
          client: client(
            MockClient(
              (_) async => http.Response(
                jsonEncode({'success': false, 'error_code': scenario.$1}),
                409,
              ),
            ),
          ),
          storage: storage(),
        ),
      );

      await expectLater(
        repository.claimOpenCall('TX209912319998', 11),
        throwsA(
          isA<ApiException>().having(
            (error) => error.kind,
            'kind',
            scenario.$2,
          ),
        ),
      );
    });
  }

  test('urgent lock posts without a body and parses lock deadline', () async {
    late http.Request request;
    final repository = DispatchRepository(
      DispatchApi(
        client: client(
          MockClient((incoming) async {
            request = incoming;
            return http.Response(
              jsonEncode({
                'success': true,
                'data': {
                  'bookingNumber': 'TX209912319997',
                  'bookingId': 10,
                  'negotiationId': 9,
                  'attemptId': 3,
                  'attemptNumber': 1,
                  'driverId': 7,
                  'status': 'LOCKED',
                  'lockExpiresAt': '2026-07-27 10:33:00.000',
                },
              }),
              200,
            );
          }),
        ),
        storage: storage(),
      ),
    );

    final result = await repository.lockUrgentCall('TX209912319997');

    expect(request.method, 'POST');
    expect(request.url.path, '/api/v1/driver/urgent-calls/TX209912319997/lock');
    expect(request.body, isEmpty);
    expect(result.negotiationId, 9);
    expect(result.lockExpiresAt, '2026-07-27 10:33:00.000');
  });

  test(
    'urgent ETA posts a strict JSON integer and parses waiting TTL',
    () async {
      late http.Request request;
      final repository = DispatchRepository(
        DispatchApi(
          client: client(
            MockClient((incoming) async {
              request = incoming;
              return http.Response(
                jsonEncode({
                  'success': true,
                  'data': {
                    'bookingNumber': 'TX209912319997',
                    'bookingId': 10,
                    'negotiationId': 9,
                    'attemptNumber': 1,
                    'driverId': 7,
                    'status': 'AWAITING_CUSTOMER',
                    'etaMinutes': 19,
                    'customerDecisionExpiresAt': '2026-07-27 10:35:00.000',
                  },
                }),
                200,
              );
            }),
          ),
          storage: storage(),
        ),
      );

      final result = await repository.submitUrgentEta('TX209912319997', 19);

      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/api/v1/driver/urgent-calls/TX209912319997/eta',
      );
      expect(jsonDecode(request.body), {'etaMinutes': 19});
      expect(result.status, 'AWAITING_CUSTOMER');
      expect(result.customerDecisionExpiresAt, '2026-07-27 10:35:00.000');
    },
  );

  for (final scenario in [
    (409, 'URGENT_ALREADY_LOCKED', ApiFailureKind.urgentAlreadyLocked),
    (400, 'URGENT_NOT_URGENT_BOOKING', ApiFailureKind.urgentNotUrgentBooking),
    (
      409,
      'URGENT_NEGOTIATION_NOT_BROADCASTING',
      ApiFailureKind.urgentNotBroadcasting,
    ),
    (400, 'URGENT_ETA_INVALID', ApiFailureKind.urgentEtaInvalid),
    (
      400,
      'URGENT_ETA_EXCEEDS_PICKUP_WINDOW',
      ApiFailureKind.urgentEtaExceedsPickupWindow,
    ),
    (403, 'URGENT_NOT_LOCKED_DRIVER', ApiFailureKind.urgentNotLockedDriver),
    (
      404,
      'URGENT_NEGOTIATION_NOT_FOUND',
      ApiFailureKind.urgentNegotiationNotFound,
    ),
    (409, 'URGENT_NOT_LOCKED', ApiFailureKind.urgentNotLocked),
    (409, 'URGENT_ETA_WINDOW_EXPIRED', ApiFailureKind.urgentEtaExpired),
    (422, 'URGENT_ETA_NOT_FAST_ENOUGH', ApiFailureKind.urgentEtaNotFastEnough),
  ]) {
    test('urgent API classifies ${scenario.$2}', () async {
      final repository = DispatchRepository(
        DispatchApi(
          client: client(
            MockClient(
              (_) async => http.Response(
                jsonEncode({
                  'success': false,
                  'error_code': scenario.$2,
                  'errors': [
                    {'minRequiredEtaMinutes': 20, 'submittedEtaMinutes': 20},
                  ],
                }),
                scenario.$1,
              ),
            ),
          ),
          storage: storage(),
        ),
      );

      await expectLater(
        scenario.$2 == 'URGENT_ALREADY_LOCKED' ||
                scenario.$2 == 'URGENT_NEGOTIATION_NOT_BROADCASTING' ||
                scenario.$2 == 'URGENT_NOT_URGENT_BOOKING'
            ? repository.lockUrgentCall('TX209912319997')
            : repository.submitUrgentEta('TX209912319997', 20),
        throwsA(
          isA<ApiException>()
              .having((error) => error.kind, 'kind', scenario.$3)
              .having(
                (error) => error.errors.first['minRequiredEtaMinutes'],
                'details',
                20,
              ),
        ),
      );
    });
  }
}

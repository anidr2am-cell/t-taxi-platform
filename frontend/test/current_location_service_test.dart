import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/services/current_location_service.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  test('requests permission only after locate is called', () async {
    var checks = 0;
    var requests = 0;
    final provider = _provider(
      checkPermission: () async {
        checks += 1;
        return LocationPermission.denied;
      },
      requestPermission: () async {
        requests += 1;
        return LocationPermission.whileInUse;
      },
    );

    expect(checks, 0);
    expect(requests, 0);

    final result = await provider.locate();

    expect(checks, 1);
    expect(requests, 1);
    expect(result.latitude, 13.7563);
  });

  test('does not request permission when already allowed', () async {
    var requests = 0;
    final provider = _provider(
      checkPermission: () async => LocationPermission.whileInUse,
      requestPermission: () async {
        requests += 1;
        return LocationPermission.whileInUse;
      },
    );

    await provider.locate();

    expect(requests, 0);
  });

  test('maps denied permission', () async {
    final provider = _provider(
      checkPermission: () async => LocationPermission.denied,
      requestPermission: () async => LocationPermission.denied,
    );

    await expectLater(
      provider.locate(),
      throwsA(_failure(CurrentLocationFailure.permissionDenied)),
    );
  });

  test('maps permanently denied permission', () async {
    final provider = _provider(
      checkPermission: () async => LocationPermission.deniedForever,
    );

    await expectLater(
      provider.locate(),
      throwsA(_failure(CurrentLocationFailure.permissionPermanentlyDenied)),
    );
  });

  test(
    'uses timed position request when browser permission is undetermined',
    () async {
      var requests = 0;
      var positionCalls = 0;
      final provider = _provider(
        checkPermission: () async => LocationPermission.unableToDetermine,
        requestPermission: () async {
          requests += 1;
          return LocationPermission.unableToDetermine;
        },
        currentPosition: (_) async {
          positionCalls += 1;
          return const CurrentLocationResult(
            latitude: 13.7563,
            longitude: 100.5018,
            accuracyMeters: 10,
          );
        },
      );

      await provider.locate();

      expect(requests, 0);
      expect(positionCalls, 1);
    },
  );

  test('maps disabled location service', () async {
    final provider = _provider(locationServiceEnabled: () async => false);

    await expectLater(
      provider.locate(),
      throwsA(_failure(CurrentLocationFailure.serviceDisabled)),
    );
  });

  test('maps position timeout', () async {
    final provider = _provider(
      currentPosition: (_) => throw TimeoutException('location'),
    );

    await expectLater(
      provider.locate(),
      throwsA(_failure(CurrentLocationFailure.timeout)),
    );
  });

  test('blocks insecure web context before requesting permission', () async {
    var checks = 0;
    final provider = _provider(
      webPlatform: true,
      isSecureWebContext: () => false,
      checkPermission: () async {
        checks += 1;
        return LocationPermission.whileInUse;
      },
    );

    await expectLater(
      provider.locate(),
      throwsA(_failure(CurrentLocationFailure.requiresHttps)),
    );
    expect(checks, 0);
  });

  test('maps unknown position errors to unavailable', () async {
    final provider = _provider(
      currentPosition: (_) => throw StateError('unavailable'),
    );

    await expectLater(
      provider.locate(),
      throwsA(_failure(CurrentLocationFailure.unavailable)),
    );
  });
}

GeolocatorCurrentLocationProvider _provider({
  bool webPlatform = false,
  bool Function()? isSecureWebContext,
  LocationServiceReader? locationServiceEnabled,
  LocationPermissionReader? checkPermission,
  LocationPermissionReader? requestPermission,
  CurrentPositionReader? currentPosition,
}) {
  return GeolocatorCurrentLocationProvider(
    webPlatform: webPlatform,
    isSecureWebContext: isSecureWebContext ?? () => true,
    locationServiceEnabled: locationServiceEnabled ?? () async => true,
    checkPermission:
        checkPermission ?? () async => LocationPermission.whileInUse,
    requestPermission:
        requestPermission ?? () async => LocationPermission.whileInUse,
    currentPosition:
        currentPosition ??
        (_) async => const CurrentLocationResult(
          latitude: 13.7563,
          longitude: 100.5018,
          accuracyMeters: 10,
        ),
  );
}

Matcher _failure(CurrentLocationFailure failure) {
  return isA<CurrentLocationException>().having(
    (error) => error.failure,
    'failure',
    failure,
  );
}

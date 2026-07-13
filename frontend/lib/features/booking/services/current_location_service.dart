import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

enum CurrentLocationFailure {
  permissionRequired,
  permissionDenied,
  permissionPermanentlyDenied,
  serviceDisabled,
  unavailable,
  timeout,
  requiresHttps,
}

class CurrentLocationException implements Exception {
  const CurrentLocationException(this.failure);

  final CurrentLocationFailure failure;
}

class CurrentLocationResult {
  const CurrentLocationResult({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
}

abstract interface class CurrentLocationProvider {
  Future<CurrentLocationResult> locate();
}

typedef LocationServiceReader = Future<bool> Function();
typedef LocationPermissionReader = Future<LocationPermission> Function();
typedef CurrentPositionReader =
    Future<CurrentLocationResult> Function(Duration timeout);

class GeolocatorCurrentLocationProvider implements CurrentLocationProvider {
  GeolocatorCurrentLocationProvider({
    this.timeout = const Duration(seconds: 10),
    bool? webPlatform,
    bool Function()? isSecureWebContext,
    LocationServiceReader? locationServiceEnabled,
    LocationPermissionReader? checkPermission,
    LocationPermissionReader? requestPermission,
    CurrentPositionReader? currentPosition,
  }) : _webPlatform = webPlatform ?? kIsWeb,
       _isSecureWebContext = isSecureWebContext ?? _defaultSecureWebContext,
       _locationServiceEnabled =
           locationServiceEnabled ?? Geolocator.isLocationServiceEnabled,
       _checkPermission = checkPermission ?? Geolocator.checkPermission,
       _requestPermission = requestPermission ?? Geolocator.requestPermission,
       _currentPosition = currentPosition ?? _readCurrentPosition;

  final Duration timeout;
  final bool _webPlatform;
  final bool Function() _isSecureWebContext;
  final LocationServiceReader _locationServiceEnabled;
  final LocationPermissionReader _checkPermission;
  final LocationPermissionReader _requestPermission;
  final CurrentPositionReader _currentPosition;

  @override
  Future<CurrentLocationResult> locate() async {
    if (_webPlatform && !_isSecureWebContext()) {
      throw const CurrentLocationException(
        CurrentLocationFailure.requiresHttps,
      );
    }

    try {
      if (!await _locationServiceEnabled()) {
        throw const CurrentLocationException(
          CurrentLocationFailure.serviceDisabled,
        );
      }

      var permission = await _checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await _requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw const CurrentLocationException(
          CurrentLocationFailure.permissionDenied,
        );
      }
      if (permission == LocationPermission.deniedForever) {
        throw const CurrentLocationException(
          CurrentLocationFailure.permissionPermanentlyDenied,
        );
      }
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse &&
          permission != LocationPermission.unableToDetermine) {
        throw const CurrentLocationException(
          CurrentLocationFailure.permissionRequired,
        );
      }

      return await _currentPosition(timeout);
    } on CurrentLocationException {
      rethrow;
    } on TimeoutException {
      throw const CurrentLocationException(CurrentLocationFailure.timeout);
    } on LocationServiceDisabledException {
      throw const CurrentLocationException(
        CurrentLocationFailure.serviceDisabled,
      );
    } on PermissionDeniedException {
      throw const CurrentLocationException(
        CurrentLocationFailure.permissionDenied,
      );
    } catch (error) {
      final message = error.toString().toLowerCase();
      if (message.contains('secure') || message.contains('https')) {
        throw const CurrentLocationException(
          CurrentLocationFailure.requiresHttps,
        );
      }
      if (message.contains('timeout') || message.contains('timed out')) {
        throw const CurrentLocationException(CurrentLocationFailure.timeout);
      }
      throw const CurrentLocationException(CurrentLocationFailure.unavailable);
    }
  }

  static bool _defaultSecureWebContext() {
    final uri = Uri.base;
    if (uri.scheme == 'https') return true;
    if (uri.scheme != 'http') return false;
    return uri.host == 'localhost' ||
        uri.host == '127.0.0.1' ||
        uri.host == '::1';
  }

  static Future<CurrentLocationResult> _readCurrentPosition(
    Duration timeout,
  ) async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: timeout,
      ),
    );
    return CurrentLocationResult(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
    );
  }
}

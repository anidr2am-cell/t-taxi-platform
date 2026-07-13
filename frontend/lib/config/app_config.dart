import 'app_config_validation.dart';

// Application configuration (Pack 18).
//
// Production builds should pass:
// `--dart-define=APP_ENV=production`
// `--dart-define=API_BASE_URL=https://api.example.com`
// `--dart-define=SOCKET_URL=https://api.example.com`
class AppConfig {
  static const String _appEnvironment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: AppConfigValidation.development,
  );

  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static const String _socketUrl = String.fromEnvironment(
    'SOCKET_URL',
    defaultValue: '',
  );

  static const String firebaseApiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
  );
  static const String firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const String firebaseMessagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const String firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
  );
  static const String firebaseAuthDomain = String.fromEnvironment(
    'FIREBASE_AUTH_DOMAIN',
  );
  static const String firebaseStorageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
  );
  static const String firebaseVapidKey = String.fromEnvironment(
    'FIREBASE_VAPID_KEY',
  );

  static String get appEnvironment =>
      AppConfigValidation.normalizeEnvironment(_appEnvironment);

  static bool get isProduction =>
      AppConfigValidation.isProductionEnvironment(appEnvironment);

  static String get apiBaseUrl => AppConfigValidation.resolveApiBaseUrl(
    appEnvironment: appEnvironment,
    apiBaseUrl: _apiBaseUrl,
  );

  static String get socketUrl => AppConfigValidation.resolveSocketUrl(
    appEnvironment: appEnvironment,
    socketUrl: _socketUrl,
    apiBaseUrl: apiBaseUrl,
  );

  static bool get isDevelopment =>
      apiBaseUrl.contains('localhost') || apiBaseUrl.contains('127.0.0.1');

  static bool get hasFirebaseWebConfig =>
      firebaseApiKey.isNotEmpty &&
      firebaseAppId.isNotEmpty &&
      firebaseMessagingSenderId.isNotEmpty &&
      firebaseProjectId.isNotEmpty;
}

enum ServiceType { airportPickup, airportDropoff, cityTransfer, golfTransfer }

extension ServiceTypeExt on ServiceType {
  String get apiValue {
    switch (this) {
      case ServiceType.airportPickup:
        return 'airport_pickup';
      case ServiceType.airportDropoff:
        return 'airport_dropoff';
      case ServiceType.cityTransfer:
        return 'city_transfer';
      case ServiceType.golfTransfer:
        return 'golf_transfer';
    }
  }

  String get labelKey {
    switch (this) {
      case ServiceType.airportPickup:
        return 'airport_pickup';
      case ServiceType.airportDropoff:
        return 'airport_dropoff';
      case ServiceType.cityTransfer:
        return 'city_transfer';
      case ServiceType.golfTransfer:
        return 'golf_transfer';
    }
  }
}

enum VehicleType { sedan, suv, vipSuv, van }

extension VehicleTypeExt on VehicleType {
  String get apiValue {
    switch (this) {
      case VehicleType.sedan:
        return 'SEDAN';
      case VehicleType.suv:
        return 'SUV';
      case VehicleType.vipSuv:
        return 'VIP_SUV';
      case VehicleType.van:
        return 'VAN';
    }
  }

  static VehicleType fromApi(String value) {
    switch (value) {
      case 'SEDAN':
        return VehicleType.sedan;
      case 'SUV':
        return VehicleType.suv;
      case 'VIP_SUV':
        return VehicleType.vipSuv;
      case 'VAN':
        return VehicleType.van;
      default:
        return VehicleType.sedan;
    }
  }
}

enum ReservationStatus {
  pending,
  confirmed,
  driverAssigned,
  completed,
  cancelled,
}

extension ReservationStatusExt on ReservationStatus {
  static ReservationStatus fromApi(String value) {
    switch (value) {
      case 'pending':
        return ReservationStatus.pending;
      case 'confirmed':
        return ReservationStatus.confirmed;
      case 'driver_assigned':
        return ReservationStatus.driverAssigned;
      case 'completed':
        return ReservationStatus.completed;
      case 'cancelled':
        return ReservationStatus.cancelled;
      default:
        return ReservationStatus.pending;
    }
  }

  String get labelKey {
    switch (this) {
      case ReservationStatus.pending:
        return 'status_pending';
      case ReservationStatus.confirmed:
        return 'status_confirmed';
      case ReservationStatus.driverAssigned:
        return 'status_driver_assigned';
      case ReservationStatus.completed:
        return 'status_completed';
      case ReservationStatus.cancelled:
        return 'status_cancelled';
    }
  }
}

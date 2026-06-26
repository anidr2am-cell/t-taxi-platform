enum BookingServiceType {
  airportPickup,
  airportDropoff,
  cityTransfer,
  golfTransfer,
}

extension BookingServiceTypeX on BookingServiceType {
  String get apiCode {
    switch (this) {
      case BookingServiceType.airportPickup:
        return 'AIRPORT_PICKUP';
      case BookingServiceType.airportDropoff:
        return 'AIRPORT_DROPOFF';
      case BookingServiceType.cityTransfer:
        return 'CITY_TRANSFER';
      case BookingServiceType.golfTransfer:
        return 'GOLF_TRANSFER';
    }
  }

  String get labelKey {
    switch (this) {
      case BookingServiceType.airportPickup:
        return 'airport_pickup';
      case BookingServiceType.airportDropoff:
        return 'airport_dropoff';
      case BookingServiceType.cityTransfer:
        return 'city_transfer';
      case BookingServiceType.golfTransfer:
        return 'golf_transfer';
    }
  }

  static BookingServiceType? fromApiCode(String? code) {
    if (code == null) return null;
    switch (code.toUpperCase()) {
      case 'AIRPORT_PICKUP':
        return BookingServiceType.airportPickup;
      case 'AIRPORT_DROPOFF':
        return BookingServiceType.airportDropoff;
      case 'CITY_TRANSFER':
        return BookingServiceType.cityTransfer;
      case 'GOLF_TRANSFER':
        return BookingServiceType.golfTransfer;
      default:
        return null;
    }
  }
}

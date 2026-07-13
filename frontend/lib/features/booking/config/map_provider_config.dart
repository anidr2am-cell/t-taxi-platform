class MapProviderConfig {
  MapProviderConfig._();

  static const tileUrlTemplate = String.fromEnvironment(
    'MAP_TILE_URL_TEMPLATE',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );

  static const reverseGeocodingEndpoint = String.fromEnvironment(
    'REVERSE_GEOCODING_ENDPOINT',
    defaultValue: 'https://nominatim.openstreetmap.org/reverse',
  );

  static const attributionUrl = 'https://www.openstreetmap.org/copyright';
  static const applicationIdentifier =
      'T-Ride/1.0 (https://github.com/anidr2am-cell/t-taxi-platform)';
}

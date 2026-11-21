bool consumeFreshBookingEntry(Uri uri) =>
    uri.queryParameters.containsKey('entry');

Map<String, dynamic>? landingRouteEntry(Uri uri) => null;

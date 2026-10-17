bool consumeFreshBookingEntry(Uri uri) =>
    uri.queryParameters.containsKey('entry');

import 'package:url_launcher/url_launcher.dart';

import '../booking/models/airport_shortcuts.dart';
import '../booking/models/location_option.dart';
import '../booking/models/thailand_registered_airports.dart';
import 'models/driver_booking.dart';

class DriverTripContact {
  static final RegExp _ambiguousCityOnly = RegExp(
    r'^(bangkok|chiang\s*mai|phuket|pattaya|rayong|hua\s*hin|thailand|th)'
    r'(,\s*(thailand|th))?$',
    caseSensitive: false,
  );

  static final RegExp _iataOnly = RegExp(
    r'^(bkk|dmk|cnx|hkt)(\s*,\s*(thailand|th))?$',
    caseSensitive: false,
  );

  static bool hasNavigableAddress(String address) => address.trim().isNotEmpty;

  static bool hasNavigableLocation(DriverBookingLocation location) =>
      googleMapsUriForLocation(location) != null;

  static bool hasCallablePhone(String? phone) {
    final normalized = phone?.replaceAll(RegExp(r'\s'), '') ?? '';
    return normalized.length >= 6;
  }

  static Future<bool> openMaps(String address) async {
    final location = DriverBookingLocation(address: address);
    return openMapsForLocation(location);
  }

  /// Google Maps link priority:
  /// 1) valid latitude + longitude
  /// 2) known Thailand airport match → verified shortcut coordinates
  /// 3) Google Place ID (+ required query)
  /// 4) precise address / place name (never city/IATA-only alone)
  static Uri? googleMapsUriForLocation(DriverBookingLocation location) {
    final explicit = _coordinateUri(location.latitude, location.longitude);
    if (explicit != null) return explicit;

    final knownAirport = resolveKnownAirport(location);
    if (knownAirport != null) {
      final airportUri = _coordinateUri(
        knownAirport.latitude,
        knownAirport.longitude,
      );
      if (airportUri != null) return airportUri;
    }

    final placeId = location.placeId?.trim();
    final hasPlaceId = placeId != null && placeId.isNotEmpty;
    final query = _mapsSearchQuery(location, knownAirport: knownAirport);

    // Google Maps Search API requires `query` together with `query_place_id`.
    // Do not open Place ID alone without a usable query label.
    if (hasPlaceId) {
      if (query == null || query.isEmpty || _isAmbiguousFallback(query)) {
        return null;
      }
      return Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': query,
        'query_place_id': placeId,
      });
    }

    if (query == null || query.isEmpty) return null;
    return Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': query,
    });
  }

  static Uri? _coordinateUri(double? lat, double? lng) {
    if (lat == null || lng == null) return null;
    if (!lat.isFinite || !lng.isFinite) return null;
    if (lat == 0 && lng == 0) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    return Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '$lat,$lng',
    });
  }

  static String? _mapsSearchQuery(
    DriverBookingLocation location, {
    LocationOption? knownAirport,
  }) {
    if (knownAirport != null) {
      final address = knownAirport.address?.trim();
      if (address != null && address.isNotEmpty) return address;
      return knownAirport.displayName;
    }

    final name = location.name?.trim();
    final address = location.address?.trim();
    final hasName = name != null && name.isNotEmpty;
    final hasAddress = address != null && address.isNotEmpty;

    if (!hasName && !hasAddress) return null;

    if (hasName && hasAddress) {
      if (name == address) {
        return _isAmbiguousFallback(name) ? null : name;
      }
      if (_isAmbiguousFallback(address)) {
        return _isAmbiguousFallback(name) ? null : '$name, Thailand';
      }
      if (_isAmbiguousFallback(name)) {
        return address;
      }
      return '$name $address';
    }

    if (hasName) {
      return _isAmbiguousFallback(name) ? null : name;
    }
    if (_isAmbiguousFallback(address!)) return null;
    return address;
  }

  static bool isAmbiguousCityOnly(String value) => _isAmbiguousFallback(value);

  static bool _isAmbiguousFallback(String value) {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return true;
    if (_ambiguousCityOnly.hasMatch(normalized)) return true;
    if (_iataOnly.hasMatch(normalized)) return true;
    return false;
  }

  /// Match a booking location to a known airport only when identity is clear.
  ///
  /// - Official airport name / "CODE — Airport" labels
  /// - IATA alone (enriched to full airport; never used as maps query text)
  /// - IATA + "airport" / official name tokens
  ///
  /// Does not treat city-only strings or unrelated "BKK Hotel" text as airports.
  static LocationOption? resolveKnownAirport(DriverBookingLocation location) {
    final name = location.name?.trim() ?? '';
    final address = location.address?.trim() ?? '';
    final haystack = '$name $address'.trim().toUpperCase();
    if (haystack.isEmpty) return null;

    final compact = haystack.replaceAll(RegExp(r'[^A-Z0-9]'), '');

    for (final airport in [
      ...ThailandRegisteredAirports.all,
      ...AirportShortcuts.all.where((a) => a.code == 'UTP'),
    ]) {
      final code = airport.code?.toUpperCase();
      if (code == null || code.isEmpty) continue;

      final official = airport.displayName
          .replaceFirst(RegExp('^$code\\s*[—-]\\s*', caseSensitive: false), '')
          .trim()
          .toUpperCase();

      if (official.length >= 8 && haystack.contains(official)) {
        return airport;
      }

      final normalizedSingle = haystack.replaceAll(RegExp(r'\s+'), ' ');
      if (_iataOnly.hasMatch(normalizedSingle) &&
          normalizedSingle.startsWith(code)) {
        return airport;
      }
      if (name.isNotEmpty &&
          address.isEmpty &&
          _iataOnly.hasMatch(name) &&
          name.toUpperCase().startsWith(code)) {
        return airport;
      }
      if (address.isNotEmpty &&
          name.isEmpty &&
          _iataOnly.hasMatch(address) &&
          address.toUpperCase().startsWith(code)) {
        return airport;
      }

      final codeToken = RegExp(
        '(^|[^A-Z0-9])$code([^A-Z0-9]|\$)',
        caseSensitive: false,
      );
      if (codeToken.hasMatch(haystack)) {
        final hasAirportWord = haystack.contains('AIRPORT');
        final hasOfficial = official.length >= 8 && haystack.contains(official);
        final labeled = RegExp(
          '$code\\s*[—-]\\s*',
          caseSensitive: false,
        ).hasMatch(haystack);
        if (hasAirportWord || hasOfficial || labeled) {
          return airport;
        }
      }

      // Compact identity like "BKKSUVARNABHUMI..."
      if (compact.contains('$code${official.replaceAll(RegExp(r'[^A-Z0-9]'), '')}') &&
          official.length >= 8) {
        return airport;
      }
    }
    return null;
  }

  /// Driver-facing label: prefer `BKK — Suvarnabhumi Airport` when matched.
  static String displayLabelFor(DriverBookingLocation location) {
    final known = resolveKnownAirport(location);
    if (known != null) return known.displayName;
    return location.displayName;
  }

  static Future<bool> openMapsForLocation(
    DriverBookingLocation location,
  ) async {
    final uri = googleMapsUriForLocation(location);
    if (uri == null || uri.scheme != 'https' || uri.host != 'www.google.com') {
      return false;
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<bool> callPhone(String phone) async {
    final normalized = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (normalized.isEmpty) return false;
    final uri = Uri.parse('tel:$normalized');
    if (!await canLaunchUrl(uri)) return false;
    return launchUrl(uri);
  }
}

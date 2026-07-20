import 'package:url_launcher/url_launcher.dart';

import 'models/driver_booking.dart';

class DriverTripContact {
  static bool hasNavigableAddress(String address) => address.trim().isNotEmpty;

  static bool hasCallablePhone(String? phone) {
    final normalized = phone?.replaceAll(RegExp(r'\s'), '') ?? '';
    return normalized.length >= 6;
  }

  static Future<bool> openMaps(String address) async {
    final query = Uri.encodeComponent(address.trim());
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$query',
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Uri? googleMapsUriForLocation(DriverBookingLocation location) {
    final lat = location.latitude;
    final lng = location.longitude;
    if (lat != null &&
        lng != null &&
        lat.isFinite &&
        lng.isFinite &&
        lat >= -90 &&
        lat <= 90 &&
        lng >= -180 &&
        lng <= 180) {
      return Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': '$lat,$lng',
      });
    }

    final placeId = location.placeId?.trim();
    final queryParts = [
      location.name?.trim(),
      location.address?.trim(),
    ].whereType<String>().where((value) => value.isNotEmpty).toList();
    if (queryParts.isEmpty) return null;
    final query = queryParts.toSet().join(' ');
    final params = {'api': '1', 'query': query};
    if (placeId != null && placeId.isNotEmpty) {
      params['query_place_id'] = placeId;
    }
    return Uri.https('www.google.com', '/maps/search/', params);
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

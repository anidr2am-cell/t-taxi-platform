import 'package:url_launcher/url_launcher.dart';

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

  static Future<bool> callPhone(String phone) async {
    final normalized = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (normalized.isEmpty) return false;
    final uri = Uri.parse('tel:$normalized');
    if (!await canLaunchUrl(uri)) return false;
    return launchUrl(uri);
  }
}

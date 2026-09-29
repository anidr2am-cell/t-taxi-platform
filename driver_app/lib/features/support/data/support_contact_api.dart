import '../../../core/network/api_client.dart';

abstract interface class SupportContactDataSource {
  Future<Uri?> getAdministratorLineUrl();
}

class SupportContactApi implements SupportContactDataSource {
  SupportContactApi({required ApiClient client}) : _client = client;

  final ApiClient _client;

  @override
  Future<Uri?> getAdministratorLineUrl() async {
    final response = await _client.getJson(
      '/api/v1/bookings/contact-channels/public',
    );
    final data = response['data'];
    if (data is! Map<String, dynamic>) return null;
    final channels = data['channels'];
    if (channels is! List) return null;
    for (final channel in channels) {
      if (channel is! Map) continue;
      if (channel['code'] != 'LINE' || channel['enabled'] == false) continue;
      final uri = Uri.tryParse(channel['addUrl']?.toString() ?? '');
      if (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty) {
        return uri;
      }
    }
    return null;
  }
}

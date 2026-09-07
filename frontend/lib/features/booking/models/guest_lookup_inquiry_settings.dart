import 'contact_channel.dart';

class GuestLookupInquirySettings {
  const GuestLookupInquirySettings({
    required this.enabled,
    required this.message,
    required this.channels,
  });

  final bool enabled;
  final String message;
  final List<ContactChannel> channels;

  factory GuestLookupInquirySettings.fromJson(Map<String, dynamic> json) {
    final rawChannels = json['channels'];
    final channels = rawChannels is List
        ? rawChannels
            .whereType<Map>()
            .map((item) => ContactChannel.fromJson(Map<String, dynamic>.from(item)))
            .where((channel) => channel.addUrl?.trim().isNotEmpty == true)
            .toList(growable: false)
        : const <ContactChannel>[];
    return GuestLookupInquirySettings(
      enabled: json['enabled'] == true,
      message: json['message'] as String? ?? '',
      channels: channels,
    );
  }

  bool get shouldShowBanner => enabled;
}

// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as web;

/// Keep the chosen customer language on reload without navigating or replacing
/// the current draft's service, entry ID, route query or attribution.
void updateCustomerLanguageUrl(String languageCode) {
  final uri = Uri.base;
  if (RegExp(r'^/(admin|driver|auth)(/|$)').hasMatch(uri.path)) return;
  try {
    final updated = uri.replace(
      queryParameters: {
        ...uri.queryParametersAll,
        'lang': [languageCode],
      },
    );
    web.window.history.replaceState(
      web.window.history.state,
      '',
      updated.toString(),
    );
  } catch (_) {
    // Language selection remains usable if browser history is unavailable.
  }
}

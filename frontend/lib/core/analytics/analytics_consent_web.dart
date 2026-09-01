import 'dart:js_interop';

import 'analytics_consent.dart';

@JS('localStorage')
external _Storage _localStorage;

extension type _Storage._(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}

class WebAnalyticsConsentStorage implements AnalyticsConsentStorage {
  @override
  String? read(String key) {
    try {
      return _localStorage.getItem(key);
    } catch (_) {
      return null;
    }
  }

  @override
  void write(String key, String value) {
    try {
      _localStorage.setItem(key, value);
    } catch (_) {}
  }

  @override
  void remove(String key) {
    try {
      _localStorage.removeItem(key);
    } catch (_) {}
  }
}

AnalyticsConsentStorage createAnalyticsConsentStorage() =>
    WebAnalyticsConsentStorage();

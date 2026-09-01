import 'dart:js_interop';

import 'marketing_attribution.dart';

@JS('localStorage')
external Storage _localStorage;

extension type Storage._(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}

class WebMarketingAttributionStorage implements MarketingAttributionStorage {
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

MarketingAttributionStorage createMarketingAttributionStorage() =>
    WebMarketingAttributionStorage();

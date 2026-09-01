import 'dart:js_interop';

@JS('trideGa4Init')
external void _trideGa4Init(String measurementId);

@JS('trideGa4UpdateConsent')
external void _trideGa4UpdateConsent(bool granted);

@JS('trideGa4Event')
external void _trideGa4Event(String name, JSObject params);

@JS('trideGa4PageView')
external void _trideGa4PageView(String path, String? title);

@JS('document')
external _Document get _document;

extension type _Document._(JSObject _) implements JSObject {
  @JS('referrer')
  external String get referrer;
}

class Ga4Bridge {
  Ga4Bridge._();

  static bool _initialized = false;
  static String? _lastPagePath;

  static void init(String measurementId) {
    if (measurementId.isEmpty || _initialized) return;
    try {
      _trideGa4Init(measurementId);
      _initialized = true;
    } catch (_) {}
  }

  static void updateConsent(bool granted) {
    try {
      _trideGa4UpdateConsent(granted);
    } catch (_) {}
  }

  static void event(String name, Map<String, Object?> params) {
    try {
      _trideGa4Event(name, params.jsify() as JSObject);
    } catch (_) {}
  }

  static void pageView(String path, {String? title}) {
    if (path.isEmpty) return;
    if (_lastPagePath == path) return;
    _lastPagePath = path;
    try {
      _trideGa4PageView(path, title);
    } catch (_) {}
  }

  static String get documentReferrer {
    try {
      return _document.referrer;
    } catch (_) {
      return '';
    }
  }
}

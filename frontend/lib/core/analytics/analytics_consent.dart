/// Analytics consent state (independent from booking functionality).
enum AnalyticsConsentStatus {
  unknown,
  granted,
  denied,
}

abstract class AnalyticsConsentStorage {
  String? read(String key);
  void write(String key, String value);
  void remove(String key);
}

class InMemoryAnalyticsConsentStorage implements AnalyticsConsentStorage {
  final Map<String, String> _values = {};

  @override
  String? read(String key) => _values[key];

  @override
  void write(String key, String value) => _values[key] = value;

  @override
  void remove(String key) => _values.remove(key);

  void clear() => _values.clear();
}

class AnalyticsConsentService {
  AnalyticsConsentService(this._storage);

  static const storageKey = 'tride_analytics_consent';

  final AnalyticsConsentStorage _storage;

  AnalyticsConsentStatus get status {
    final raw = _storage.read(storageKey);
    switch (raw) {
      case 'granted':
        return AnalyticsConsentStatus.granted;
      case 'denied':
        return AnalyticsConsentStatus.denied;
      default:
        return AnalyticsConsentStatus.unknown;
    }
  }

  bool get isGranted => status == AnalyticsConsentStatus.granted;

  bool get isDenied => status == AnalyticsConsentStatus.denied;

  bool get needsPrompt => status == AnalyticsConsentStatus.unknown;

  void grant() => _storage.write(storageKey, 'granted');

  void deny() => _storage.write(storageKey, 'denied');

  void reset() => _storage.remove(storageKey);
}

import 'analytics_consent.dart';

class StubAnalyticsConsentStorage implements AnalyticsConsentStorage {
  @override
  String? read(String key) => null;

  @override
  void write(String key, String value) {}

  @override
  void remove(String key) {}
}

AnalyticsConsentStorage createAnalyticsConsentStorage() =>
    StubAnalyticsConsentStorage();

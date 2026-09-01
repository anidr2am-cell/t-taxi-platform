import 'marketing_attribution.dart';

class StubMarketingAttributionStorage implements MarketingAttributionStorage {
  @override
  String? read(String key) => null;

  @override
  void write(String key, String value) {}

  @override
  void remove(String key) {}
}

MarketingAttributionStorage createMarketingAttributionStorage() =>
    StubMarketingAttributionStorage();

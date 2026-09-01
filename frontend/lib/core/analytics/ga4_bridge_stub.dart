class Ga4Bridge {
  Ga4Bridge._();

  static void init(String measurementId) {}

  static void updateConsent(bool granted) {}

  static void event(String name, Map<String, Object?> params) {}

  static void pageView(String path, {String? title}) {}

  static String get documentReferrer => '';
}

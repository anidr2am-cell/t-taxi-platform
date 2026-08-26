abstract class LineOAuthStateStorage {
  static const storageKey = 'line_oauth_state';

  Future<void> save(String state);

  Future<String?> load();

  Future<String?> loadAndClear();

  Future<void> clear();
}

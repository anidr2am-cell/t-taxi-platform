import '../models/line_oauth_state_storage.dart';

class MemoryLineOAuthStateStorage implements LineOAuthStateStorage {
  MemoryLineOAuthStateStorage([this._state]);

  String? _state;

  @override
  Future<void> save(String state) async {
    _state = state;
  }

  @override
  Future<String?> load() async => _state;

  @override
  Future<String?> loadAndClear() async {
    final value = _state;
    _state = null;
    return value;
  }

  @override
  Future<void> clear() async {
    _state = null;
  }
}

LineOAuthStateStorage createLineOAuthStateStorage() {
  return MemoryLineOAuthStateStorage();
}

import '../models/line_oauth_callback_guard.dart';

class MemoryLineOAuthCallbackGuardStorage
    implements LineOAuthCallbackGuardStorage {
  MemoryLineOAuthCallbackGuardStorage([Map<String, String>? store])
      : _store = store ?? <String, String>{};

  final Map<String, String> _store;

  @override
  Future<LineOAuthCallbackGuardRecord?> load() async {
    return decodeLineOAuthCallbackGuardRecord(_store);
  }

  @override
  Future<void> save(LineOAuthCallbackGuardRecord record) async {
    _store
      ..clear()
      ..addAll(encodeLineOAuthCallbackGuardRecord(record));
  }

  @override
  Future<void> clear() async {
    _store.clear();
  }
}

LineOAuthCallbackGuardStorage createLineOAuthCallbackGuardStorage() {
  return MemoryLineOAuthCallbackGuardStorage();
}

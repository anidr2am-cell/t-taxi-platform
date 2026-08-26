import '../models/kakao_oauth_callback_guard.dart';

class MemoryKakaoOAuthCallbackGuardStorage
    implements KakaoOAuthCallbackGuardStorage {
  MemoryKakaoOAuthCallbackGuardStorage([Map<String, String>? store])
      : _store = store ?? <String, String>{};

  final Map<String, String> _store;

  @override
  Future<KakaoOAuthCallbackGuardRecord?> load() async {
    return decodeKakaoOAuthCallbackGuardRecord(_store);
  }

  @override
  Future<void> save(KakaoOAuthCallbackGuardRecord record) async {
    _store
      ..clear()
      ..addAll(encodeKakaoOAuthCallbackGuardRecord(record));
  }

  @override
  Future<void> clear() async {
    _store.clear();
  }
}

KakaoOAuthCallbackGuardStorage createKakaoOAuthCallbackGuardStorage() {
  return MemoryKakaoOAuthCallbackGuardStorage();
}

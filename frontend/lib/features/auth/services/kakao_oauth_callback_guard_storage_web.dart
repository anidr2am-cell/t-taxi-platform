// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import '../models/kakao_oauth_callback_guard.dart';
import 'kakao_oauth_callback_guard_storage_memory.dart';

class SessionStorageKakaoOAuthCallbackGuardStorage
    implements KakaoOAuthCallbackGuardStorage {
  @override
  Future<KakaoOAuthCallbackGuardRecord?> load() async {
    final storage = html.window.sessionStorage;
    return decodeKakaoOAuthCallbackGuardRecord({
      KakaoOAuthCallbackGuardStorage.processedCodeKey:
          storage[KakaoOAuthCallbackGuardStorage.processedCodeKey] ?? '',
      KakaoOAuthCallbackGuardStorage.processedOutcomeKey:
          storage[KakaoOAuthCallbackGuardStorage.processedOutcomeKey] ?? '',
      KakaoOAuthCallbackGuardStorage.processedReturnContextKey:
          storage[KakaoOAuthCallbackGuardStorage.processedReturnContextKey] ??
              '',
    });
  }

  @override
  Future<void> save(KakaoOAuthCallbackGuardRecord record) async {
    final storage = html.window.sessionStorage;
    final encoded = encodeKakaoOAuthCallbackGuardRecord(record);
    storage
      ..remove(KakaoOAuthCallbackGuardStorage.processedReturnContextKey)
      ..[KakaoOAuthCallbackGuardStorage.processedCodeKey] =
          encoded[KakaoOAuthCallbackGuardStorage.processedCodeKey]!
      ..[KakaoOAuthCallbackGuardStorage.processedOutcomeKey] =
          encoded[KakaoOAuthCallbackGuardStorage.processedOutcomeKey]!;

    final returnContextRaw =
        encoded[KakaoOAuthCallbackGuardStorage.processedReturnContextKey];
    if (returnContextRaw != null) {
      storage[KakaoOAuthCallbackGuardStorage.processedReturnContextKey] =
          returnContextRaw;
    }
  }

  @override
  Future<void> clear() async {
    final storage = html.window.sessionStorage;
    storage
      ..remove(KakaoOAuthCallbackGuardStorage.processedCodeKey)
      ..remove(KakaoOAuthCallbackGuardStorage.processedOutcomeKey)
      ..remove(KakaoOAuthCallbackGuardStorage.processedReturnContextKey);
  }
}

KakaoOAuthCallbackGuardStorage createKakaoOAuthCallbackGuardStorage() {
  return SessionStorageKakaoOAuthCallbackGuardStorage();
}

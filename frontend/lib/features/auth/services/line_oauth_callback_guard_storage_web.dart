// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import '../models/line_oauth_callback_guard.dart';
import 'line_oauth_callback_guard_storage_memory.dart';

class SessionStorageLineOAuthCallbackGuardStorage
    implements LineOAuthCallbackGuardStorage {
  @override
  Future<LineOAuthCallbackGuardRecord?> load() async {
    final storage = html.window.sessionStorage;
    return decodeLineOAuthCallbackGuardRecord({
      LineOAuthCallbackGuardStorage.processedCodeKey:
          storage[LineOAuthCallbackGuardStorage.processedCodeKey] ?? '',
      LineOAuthCallbackGuardStorage.processedOutcomeKey:
          storage[LineOAuthCallbackGuardStorage.processedOutcomeKey] ?? '',
      LineOAuthCallbackGuardStorage.processedReturnContextKey:
          storage[LineOAuthCallbackGuardStorage.processedReturnContextKey] ??
              '',
    });
  }

  @override
  Future<void> save(LineOAuthCallbackGuardRecord record) async {
    final storage = html.window.sessionStorage;
    final encoded = encodeLineOAuthCallbackGuardRecord(record);
    storage
      ..remove(LineOAuthCallbackGuardStorage.processedReturnContextKey)
      ..[LineOAuthCallbackGuardStorage.processedCodeKey] =
          encoded[LineOAuthCallbackGuardStorage.processedCodeKey]!
      ..[LineOAuthCallbackGuardStorage.processedOutcomeKey] =
          encoded[LineOAuthCallbackGuardStorage.processedOutcomeKey]!;
    final returnContextRaw =
        encoded[LineOAuthCallbackGuardStorage.processedReturnContextKey];
    if (returnContextRaw != null) {
      storage[LineOAuthCallbackGuardStorage.processedReturnContextKey] =
          returnContextRaw;
    }
  }

  @override
  Future<void> clear() async {
    html.window.sessionStorage
      ..remove(LineOAuthCallbackGuardStorage.processedCodeKey)
      ..remove(LineOAuthCallbackGuardStorage.processedOutcomeKey)
      ..remove(LineOAuthCallbackGuardStorage.processedReturnContextKey);
  }
}

LineOAuthCallbackGuardStorage createLineOAuthCallbackGuardStorage() {
  return SessionStorageLineOAuthCallbackGuardStorage();
}

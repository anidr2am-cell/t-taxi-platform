// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import '../models/line_oauth_state_storage.dart';
import 'line_oauth_state_storage_memory.dart';

class SessionStorageLineOAuthStateStorage implements LineOAuthStateStorage {
  @override
  Future<void> save(String state) async {
    html.window.sessionStorage[LineOAuthStateStorage.storageKey] = state;
  }

  @override
  Future<String?> load() async {
    final value =
        html.window.sessionStorage[LineOAuthStateStorage.storageKey]?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  @override
  Future<String?> loadAndClear() async {
    final value = await load();
    await clear();
    return value;
  }

  @override
  Future<void> clear() async {
    html.window.sessionStorage.remove(LineOAuthStateStorage.storageKey);
  }
}

LineOAuthStateStorage createLineOAuthStateStorage() {
  return SessionStorageLineOAuthStateStorage();
}

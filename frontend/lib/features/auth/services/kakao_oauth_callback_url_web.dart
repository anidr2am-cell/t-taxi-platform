// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'kakao_oauth_callback_url_stub.dart';

void stripKakaoCallbackCodeFromBrowserUrl(Uri uri) {
  debugStripKakaoCallbackCodeHook?.call(uri);
  if (uri.path != '/auth/kakao/callback') {
    return;
  }

  final cleaned = buildKakaoCallbackUriWithoutCode(uri);
  final nextUrl = cleaned.hasQuery ? '${cleaned.path}?${cleaned.query}' : cleaned.path;
  html.window.history.replaceState(null, '', nextUrl);
}

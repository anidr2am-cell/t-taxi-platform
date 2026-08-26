// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'line_oauth_callback_url_stub.dart';

void stripLineCallbackCodeFromBrowserUrl(Uri uri) {
  debugStripLineCallbackCodeHook?.call(uri);
  if (uri.path != '/auth/line/callback') {
    return;
  }

  final cleaned = buildLineCallbackUriWithoutCode(uri);
  final nextUrl =
      cleaned.hasQuery ? '${cleaned.path}?${cleaned.query}' : cleaned.path;
  html.window.history.replaceState(null, '', nextUrl);
}

import 'package:flutter/foundation.dart';

@visibleForTesting
void Function(Uri uri)? debugStripKakaoCallbackCodeHook;

Uri buildKakaoCallbackUriWithoutCode(Uri uri) {
  if (!uri.queryParameters.containsKey('code')) {
    return uri;
  }

  final params = Map<String, String>.from(uri.queryParameters)..remove('code');
  return uri.replace(queryParameters: params);
}

void stripKakaoCallbackCodeFromBrowserUrl(Uri uri) {
  debugStripKakaoCallbackCodeHook?.call(uri);
}

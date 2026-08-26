import 'package:flutter/foundation.dart';

@visibleForTesting
void Function(Uri uri)? debugStripLineCallbackCodeHook;

Uri buildLineCallbackUriWithoutCode(Uri uri) {
  if (!uri.queryParameters.containsKey('code') &&
      !uri.queryParameters.containsKey('state')) {
    return uri;
  }

  final params = Map<String, String>.from(uri.queryParameters)
    ..remove('code')
    ..remove('state');
  if (params.isEmpty) {
    return Uri(
      scheme: uri.scheme,
      userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
      fragment: uri.fragment.isEmpty ? null : uri.fragment,
    );
  }
  return uri.replace(queryParameters: params);
}

void stripLineCallbackCodeFromBrowserUrl(Uri uri) {
  debugStripLineCallbackCodeHook?.call(uri);
}

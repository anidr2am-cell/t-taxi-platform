Uri buildKakaoCallbackUriWithoutCode(Uri uri) {
  if (!uri.queryParameters.containsKey('code')) {
    return uri;
  }

  final params = Map<String, String>.from(uri.queryParameters)..remove('code');
  return uri.replace(queryParameters: params);
}

void stripKakaoCallbackCodeFromBrowserUrl(Uri uri) {}

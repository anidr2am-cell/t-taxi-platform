class KakaoOAuthLauncher {
  const KakaoOAuthLauncher();

  Future<void> redirectToAuthorization(Uri authorizationUri) async {
    throw UnsupportedError(
      'Kakao OAuth redirect is only supported on Flutter web.',
    );
  }
}

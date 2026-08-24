import 'dart:html' as html;

class KakaoOAuthLauncher {
  const KakaoOAuthLauncher();

  Future<void> redirectToAuthorization(Uri authorizationUri) async {
    html.window.location.assign(authorizationUri.toString());
  }
}

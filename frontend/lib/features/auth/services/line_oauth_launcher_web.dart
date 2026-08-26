import 'dart:html' as html;

class LineOAuthLauncher {
  const LineOAuthLauncher();

  Future<void> redirectToAuthorization(Uri authorizationUri) async {
    html.window.location.assign(authorizationUri.toString());
  }
}

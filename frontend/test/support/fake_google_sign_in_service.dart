import 'dart:async';

import 'package:frontend/features/auth/services/google_sign_in_service.dart';
import 'package:google_sign_in/google_sign_in.dart';

class FakeGoogleSignInService extends GoogleSignInService {
  FakeGoogleSignInService({this.idToken = 'mock-google-id-token'}) {
    markInitializedForTest();
  }

  final String? idToken;
  final StreamController<GoogleSignInAuthenticationEvent> _eventsController =
      StreamController<GoogleSignInAuthenticationEvent>.broadcast();

  @override
  Stream<GoogleSignInAuthenticationEvent> get authenticationEvents =>
      _eventsController.stream;

  @override
  Future<String?> authenticateAndGetIdToken() async => idToken;

  void emitSignIn({String idToken = 'mock-google-id-token'}) {
    _eventsController.add(
      GoogleSignInAuthenticationEventSignIn(
        user: FakeGoogleSignInAccount(idToken),
      ),
    );
  }

  Future<void> close() => _eventsController.close();
}

class FakeGoogleSignInAccount implements GoogleSignInAccount {
  FakeGoogleSignInAccount(this._idToken);

  final String _idToken;

  @override
  GoogleSignInAuthentication get authentication =>
      GoogleSignInAuthentication(idToken: _idToken);

  @override
  GoogleSignInAuthorizationClient get authorizationClient =>
      throw UnimplementedError();

  @override
  String? get displayName => 'Test User';

  @override
  String get email => 'test@example.com';

  @override
  String get id => 'test-id';

  @override
  String? get photoUrl => null;
}

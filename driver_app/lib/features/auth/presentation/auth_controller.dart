import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../data/auth_models.dart';
import '../data/auth_repository.dart';

enum AuthStatus { checking, signedOut, submitting, signedIn, restoreError }

class AuthController extends ChangeNotifier {
  AuthController(this._repository);

  final AuthRepository _repository;

  AuthStatus status = AuthStatus.checking;
  AuthSession? session;
  ApiException? lastError;

  Future<void> initialize() async {
    status = AuthStatus.checking;
    lastError = null;
    notifyListeners();
    try {
      session = await _repository.restoreSession();
      status = session == null ? AuthStatus.signedOut : AuthStatus.signedIn;
    } on ApiException catch (error) {
      status = AuthStatus.restoreError;
      lastError = error;
    } catch (_) {
      status = AuthStatus.restoreError;
      lastError = const ApiException(ApiFailureKind.unknown);
    }
    notifyListeners();
  }

  Future<void> login(String loginId, String password) async {
    if (status == AuthStatus.submitting) return;
    status = AuthStatus.submitting;
    lastError = null;
    notifyListeners();
    try {
      session = await _repository.login(loginId, password);
      status = AuthStatus.signedIn;
    } on ApiException catch (error) {
      status = AuthStatus.signedOut;
      lastError = error;
    } catch (_) {
      status = AuthStatus.signedOut;
      lastError = const ApiException(ApiFailureKind.unknown);
    }
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await _repository.logout();
    } finally {
      session = null;
      lastError = null;
      status = AuthStatus.signedOut;
      notifyListeners();
    }
  }

  Future<void> expireSession() async {
    await _repository.clearLocalSession();
    session = null;
    lastError = const ApiException(ApiFailureKind.unauthorized);
    status = AuthStatus.signedOut;
    notifyListeners();
  }
}

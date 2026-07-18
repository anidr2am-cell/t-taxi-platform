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
  String? errorMessage;

  Future<void> initialize() async {
    status = AuthStatus.checking;
    errorMessage = null;
    notifyListeners();
    try {
      session = await _repository.restoreSession();
      status = session == null ? AuthStatus.signedOut : AuthStatus.signedIn;
    } on ApiException catch (error) {
      status = AuthStatus.restoreError;
      errorMessage = error.userMessage;
    } catch (_) {
      status = AuthStatus.restoreError;
      errorMessage = const ApiException(ApiFailureKind.unknown).userMessage;
    }
    notifyListeners();
  }

  Future<void> login(String loginId, String password) async {
    if (status == AuthStatus.submitting) return;
    status = AuthStatus.submitting;
    errorMessage = null;
    notifyListeners();
    try {
      session = await _repository.login(loginId, password);
      status = AuthStatus.signedIn;
    } on ApiException catch (error) {
      status = AuthStatus.signedOut;
      errorMessage = error.userMessage;
    } catch (_) {
      status = AuthStatus.signedOut;
      errorMessage = const ApiException(ApiFailureKind.unknown).userMessage;
    }
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await _repository.logout();
    } finally {
      session = null;
      errorMessage = null;
      status = AuthStatus.signedOut;
      notifyListeners();
    }
  }
}

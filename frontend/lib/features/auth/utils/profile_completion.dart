import '../controllers/auth_controller.dart';
import '../models/auth_user.dart';

bool authUserNeedsProfileCompletion(AuthUser? user) {
  if (user == null) {
    return false;
  }
  final phone = user.phone?.trim();
  return phone == null || phone.isEmpty;
}

bool authNeedsProfileCompletion(AuthController controller) {
  return controller.isLoggedIn &&
      authUserNeedsProfileCompletion(controller.user);
}

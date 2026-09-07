import 'package:flutter/material.dart';

import '../controllers/auth_controller.dart';
import '../services/profile_completion_navigation.dart';
import '../utils/profile_completion.dart';
import '../widgets/booking_social_login_section.dart';

class ProfileCompletionGate extends StatefulWidget {
  const ProfileCompletionGate({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<ProfileCompletionGate> createState() => _ProfileCompletionGateState();
}

class _ProfileCompletionGateState extends State<ProfileCompletionGate> {
  bool _redirectScheduled = false;

  void _scheduleRedirect(AuthController authController) {
    if (_redirectScheduled) {
      return;
    }
    _redirectScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _redirectScheduled = false;
      if (!mounted) {
        return;
      }
      await redirectToProfileCompletionIfNeeded(
        authController: authController,
        returnContext: authController.pendingProfileCompletionReturnContext,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final authController = AuthScope.of(context);
    return ListenableBuilder(
      listenable: authController,
      builder: (context, _) {
        if (authController.isInitialized &&
            authNeedsProfileCompletion(authController)) {
          _scheduleRedirect(authController);
        }
        return widget.child;
      },
    );
  }
}

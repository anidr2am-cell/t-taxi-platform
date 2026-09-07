import 'package:flutter/material.dart';

import '../pages/profile_completion_page.dart';
import '../utils/profile_completion.dart';
import '../widgets/booking_social_login_section.dart';

class ProfileCompletionGate extends StatelessWidget {
  const ProfileCompletionGate({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final authController = AuthScope.of(context);
    return ListenableBuilder(
      listenable: authController,
      builder: (context, _) {
        if (!authController.isInitialized) {
          return child;
        }

        if (authNeedsProfileCompletion(authController)) {
          final routeArgs = ModalRoute.of(context)?.settings.arguments;
          final returnContext = routeArgs is ProfileCompletionRouteArgs
              ? routeArgs.returnContext
              : null;
          return ProfileCompletionPage(returnContext: returnContext);
        }

        return child;
      },
    );
  }
}

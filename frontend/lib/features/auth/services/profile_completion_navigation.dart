import 'package:flutter/material.dart';

import '../../../core/navigation/app_navigator.dart';
import '../controllers/auth_controller.dart';
import '../models/social_login_return_context.dart';
import '../pages/profile_completion_page.dart';
import '../utils/profile_completion.dart';

bool profileCompletionRedirectInFlight = false;

String? topRouteName(NavigatorState navigator) {
  Route<dynamic>? topRoute;
  navigator.popUntil((route) {
    topRoute = route;
    return true;
  });
  return topRoute?.settings.name;
}

bool isCurrentRouteProfileCompletion(NavigatorState navigator) {
  return topRouteName(navigator) == ProfileCompletionPage.routeName;
}

Future<void> redirectToProfileCompletionIfNeeded({
  required AuthController authController,
  SocialLoginReturnContext? returnContext,
}) async {
  if (!authNeedsProfileCompletion(authController)) {
    return;
  }

  final navigator = appNavigatorKey.currentState;
  if (navigator == null) {
    return;
  }

  if (isCurrentRouteProfileCompletion(navigator)) {
    return;
  }

  if (profileCompletionRedirectInFlight) {
    return;
  }

  profileCompletionRedirectInFlight = true;
  try {
    final resolvedReturnContext =
        returnContext ?? authController.pendingProfileCompletionReturnContext;

    await navigator.pushNamedAndRemoveUntil(
      ProfileCompletionPage.routeName,
      (_) => false,
      arguments: resolvedReturnContext != null
          ? ProfileCompletionRouteArgs(returnContext: resolvedReturnContext)
          : null,
    );
  } finally {
    profileCompletionRedirectInFlight = false;
  }
}

import 'package:flutter/material.dart';

import '../../booking/pages/booking_complete_page.dart';
import '../controllers/auth_controller.dart';
import '../models/social_login_return_context.dart';
import '../services/profile_completion_navigation.dart';
import '../utils/profile_completion.dart';

const kBookingCompleteRouteName = '/booking/complete';

Future<void> navigateAfterAuthenticatedSession(
  BuildContext context, {
  required AuthController authController,
  SocialLoginReturnContext? returnContext,
}) async {
  if (!context.mounted) {
    return;
  }

  if (authNeedsProfileCompletion(authController)) {
    authController.setPendingProfileCompletionReturnContext(returnContext);
    await redirectToProfileCompletionIfNeeded(
      authController: authController,
      returnContext: returnContext,
    );
    return;
  }

  await navigateToSocialLoginReturnContext(
    context,
    authController: authController,
    returnContext: returnContext,
  );
}

Future<void> navigateToSocialLoginReturnContext(
  BuildContext context, {
  required AuthController authController,
  SocialLoginReturnContext? returnContext,
}) async {
  if (!context.mounted) {
    return;
  }

  authController.clearPendingProfileCompletionReturnContext();

  if (returnContext?.returnToHome == true) {
    await Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    return;
  }

  final destination = returnContext == null || returnContext.result == null
      ? const _SocialLoginFallbackPage()
      : BookingCompletePage(
          authController: authController,
          result: returnContext.result!,
          serviceLabel: returnContext.serviceLabel,
          origin: returnContext.origin,
          destination: returnContext.destination,
          serviceTypeCode: returnContext.serviceTypeCode,
          originAirportCode: returnContext.originAirportCode,
          nameSignRequested: returnContext.nameSignRequested,
          customerPhone: returnContext.customerPhone,
          scheduledPickupAt: returnContext.scheduledPickupAt,
          selectedVehicle: returnContext.selectedVehicle,
          enableCustomerTools: returnContext.enableCustomerTools,
        );

  await Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: kBookingCompleteRouteName),
      builder: (_) => destination,
    ),
    (_) => false,
  );
}

class _SocialLoginFallbackPage extends StatelessWidget {
  const _SocialLoginFallbackPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('T-Rider')),
      body: const Center(child: Text('Sign-in complete')),
    );
  }
}

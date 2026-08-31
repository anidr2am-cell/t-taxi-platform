import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/widgets/booking_social_login_section.dart';
import 'landing_login_prompt_banner.dart';

class LandingSocialLoginSection extends StatefulWidget {
  const LandingSocialLoginSection({super.key, this.authController});

  final AuthController? authController;

  @override
  State<LandingSocialLoginSection> createState() =>
      _LandingSocialLoginSectionState();
}

class _LandingSocialLoginSectionState extends State<LandingSocialLoginSection> {
  AuthController _resolveController(BuildContext context) {
    return widget.authController ?? AuthScope.of(context);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _resolveController(context);
    final l10n = context.l10n;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!controller.isInitialized) {
          return const SizedBox.shrink();
        }

        return Padding(
          key: const Key('landing_social_login_section'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: controller.isLoggedIn
              ? AppUi.surfaceCard(
                  child: _LoggedInView(
                    l10n: l10n,
                    displayName: controller.user!.displayLabel,
                    isLoading: controller.isLoading,
                    onViewMyBookings: () =>
                        Navigator.of(context).pushNamed('/my-bookings'),
                    onSignOut: controller.isLoading
                        ? null
                        : () => controller.signOut(),
                  ),
                )
              : const LandingLoginPromptBanner(),
        );
      },
    );
  }
}

class _LoggedInView extends StatelessWidget {
  const _LoggedInView({
    required this.l10n,
    required this.displayName,
    required this.isLoading,
    required this.onViewMyBookings,
    required this.onSignOut,
  });

  final AppLocalizations l10n;
  final String displayName;
  final bool isLoading;
  final VoidCallback onViewMyBookings;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final greeting = l10n
        .t('landing_logged_in_greeting')
        .replaceAll('{name}', displayName);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          greeting,
          style: const TextStyle(
            color: AppTokens.textSecondary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: AppTokens.spaceMd),
        Wrap(
          spacing: AppTokens.spaceSm,
          runSpacing: AppTokens.spaceSm,
          children: [
            OutlinedButton(
              key: const Key('landing_my_bookings_button'),
              onPressed: isLoading ? null : onViewMyBookings,
              child: Text(l10n.t('landing_my_bookings_button')),
            ),
            TextButton(
              key: const Key('landing_logout_button'),
              onPressed: onSignOut,
              child: Text(l10n.t('landing_logout_button')),
            ),
          ],
        ),
      ],
    );
  }
}

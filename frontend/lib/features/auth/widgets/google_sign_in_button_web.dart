import 'package:flutter/material.dart';
import 'package:google_sign_in_web/web_only.dart'
    show
        GSIButtonConfiguration,
        GSIButtonSize,
        GSIButtonText,
        GSIButtonTheme,
        renderButton;

import '../../../widgets/app_ui.dart';

class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.label,
    required this.locale,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final String locale;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return AppUi.primaryButton(
        label: label,
        icon: Icons.login,
        onPressed: null,
        loading: true,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : 320.0;
        return SizedBox(
          width: width,
          height: 50,
          child: Align(
            alignment: Alignment.center,
            child: renderButton(
              configuration: GSIButtonConfiguration(
                text: GSIButtonText.continueWith,
                size: GSIButtonSize.large,
                theme: GSIButtonTheme.outline,
                minimumWidth: width.clamp(200, 400),
                locale: locale,
              ),
            ),
          ),
        );
      },
    );
  }
}

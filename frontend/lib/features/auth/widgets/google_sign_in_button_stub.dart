import 'package:flutter/material.dart';

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
    return AppUi.primaryButton(
      label: label,
      icon: Icons.login,
      onPressed: onPressed,
      loading: loading,
    );
  }
}

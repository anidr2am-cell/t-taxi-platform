import 'package:flutter/material.dart';

import '../../../widgets/app_ui.dart';

class WizardLoadingView extends StatelessWidget {
  final String? message;

  const WizardLoadingView({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return AppUi.loadingState(message: message);
  }
}

class WizardErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const WizardErrorView({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return AppUi.errorState(message: message, onRetry: onRetry);
  }
}

class WizardEmptyView extends StatelessWidget {
  final String message;

  const WizardEmptyView({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return AppUi.emptyState(title: message, icon: Icons.search_off_outlined);
  }
}

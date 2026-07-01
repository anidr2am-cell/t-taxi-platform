import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
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
    final l10n = context.l10n;
    return AppUi.errorState(
      message: l10n.t(message),
      onRetry: onRetry,
      retryLabel: l10n.t('ui_retry'),
    );
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

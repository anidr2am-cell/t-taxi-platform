import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';

class AdminCustomerPreferenceOptions {
  const AdminCustomerPreferenceOptions({
    required this.preferFemaleDriver,
    required this.preferSmokingVehicle,
  });

  final bool preferFemaleDriver;
  final bool preferSmokingVehicle;

  bool get hasAny => preferFemaleDriver || preferSmokingVehicle;

  factory AdminCustomerPreferenceOptions.fromMap(Map<String, dynamic>? source) {
    if (source == null) {
      return const AdminCustomerPreferenceOptions(
        preferFemaleDriver: false,
        preferSmokingVehicle: false,
      );
    }
    final options = source['options'] is Map
        ? Map<String, dynamic>.from(source['options'] as Map)
        : source;
    return AdminCustomerPreferenceOptions(
      preferFemaleDriver: options['preferFemaleDriver'] == true,
      preferSmokingVehicle: options['preferSmokingVehicle'] == true,
    );
  }

  List<String> labels(AppLocalizations l10n) {
    final labels = <String>[];
    if (preferFemaleDriver) {
      labels.add(l10n.t('booking_prefer_female_driver'));
    }
    if (preferSmokingVehicle) {
      labels.add(l10n.t('booking_prefer_smoking_vehicle'));
    }
    return labels;
  }

  String? summaryText(AppLocalizations l10n) {
    final parts = labels(l10n);
    if (parts.isEmpty) return null;
    return '${l10n.t('admin_customer_preference_summary_prefix')} ${parts.join(' / ')}';
  }
}

class AdminCustomerPreferenceBanner extends StatelessWidget {
  const AdminCustomerPreferenceBanner({
    super.key,
    required this.options,
  });

  final AdminCustomerPreferenceOptions options;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final summary = options.summaryText(l10n);
    if (summary == null) return const SizedBox.shrink();

    return AppUi.surfaceCard(
      backgroundColor: AppTokens.infoLight,
      padding: const EdgeInsets.all(12),
      child: Text(
        summary,
        style: const TextStyle(
          color: AppTokens.textSecondary,
          fontSize: 13,
          height: 1.45,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class AdminCustomerPreferenceBadges extends StatelessWidget {
  const AdminCustomerPreferenceBadges({
    super.key,
    required this.options,
  });

  final AdminCustomerPreferenceOptions options;

  @override
  Widget build(BuildContext context) {
    if (!options.hasAny) return const SizedBox.shrink();

    final l10n = context.l10n;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (options.preferFemaleDriver)
          AppUi.statusBadge(
            l10n.t('booking_prefer_female_driver'),
            tone: AppStatusTone.info,
          ),
        if (options.preferSmokingVehicle)
          AppUi.statusBadge(
            l10n.t('booking_prefer_smoking_vehicle'),
            tone: AppStatusTone.info,
          ),
      ],
    );
  }
}

class AdminCustomerPreferenceQueueBadge extends StatelessWidget {
  const AdminCustomerPreferenceQueueBadge({
    super.key,
    required this.options,
  });

  final AdminCustomerPreferenceOptions options;

  @override
  Widget build(BuildContext context) {
    final summary = options.summaryText(context.l10n);
    if (summary == null) return const SizedBox.shrink();

    return Tooltip(
      message: summary,
      child: AppUi.statusBadge(
        context.l10n.t('admin_customer_preference_badge'),
        tone: AppStatusTone.info,
      ),
    );
  }
}

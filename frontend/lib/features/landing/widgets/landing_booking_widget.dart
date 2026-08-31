import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../booking/models/location_option.dart';
import '../../booking/models/service_type_option.dart';
import '../../booking/widgets/step_destination_select.dart';
import '../../booking/widgets/step_origin_select.dart';
import '../models/landing_booking_draft.dart';
import '../models/landing_service_options.dart';
import 'landing_clickable_styles.dart';

class LandingBookingWidget extends StatelessWidget {
  const LandingBookingWidget({
    super.key,
    required this.draft,
    required this.languageCode,
    required this.onServiceSelected,
    required this.onOriginSelected,
    required this.onDestinationSelected,
    required this.onSubmit,
  });

  final LandingBookingDraft draft;
  final String languageCode;
  final ValueChanged<BookingServiceType> onServiceSelected;
  final ValueChanged<LocationOption> onOriginSelected;
  final ValueChanged<LocationOption> onDestinationSelected;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Container(
      key: const Key('landing_booking_widget'),
      width: 360,
      padding: const EdgeInsets.all(AppTokens.cardPadding),
      decoration: AppTokens.cardDecoration(
        color: Colors.white.withValues(alpha: 0.96),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.t('landing_hero_cta'),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.t('select_service'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          _ServiceSegmentRow(
            selected: draft.serviceType,
            onSelected: onServiceSelected,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.t('origin'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          StepOriginSelect(
            embedded: true,
            serviceType: draft.serviceType,
            selected: draft.origin,
            languageCode: languageCode,
            onSelected: onOriginSelected,
          ),
          const SizedBox(height: 10),
          Text(
            l10n.t('destination'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          StepDestinationSelect(
            embedded: true,
            serviceType: draft.serviceType,
            selected: draft.destination,
            languageCode: languageCode,
            onSelected: onDestinationSelected,
          ),
          const SizedBox(height: 16),
          Semantics(
            button: true,
            label: l10n.t('landing_hero_cta'),
            child: FilledButton(
              key: const Key('landing_booking_submit'),
              onPressed: onSubmit,
              style: LandingClickableStyles.heroCtaStyle(compact: false),
              child: Text(l10n.t('landing_hero_cta')),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceSegmentRow extends StatelessWidget {
  const _ServiceSegmentRow({
    required this.selected,
    required this.onSelected,
  });

  final BookingServiceType? selected;
  final ValueChanged<BookingServiceType> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Row(
      key: const Key('landing_booking_service_row'),
      children: [
        for (var index = 0; index < landingServiceOptions.length; index++) ...[
          if (index > 0) const SizedBox(width: 6),
          Expanded(
            child: _ServiceSegment(
              key: Key(
                'landing_booking_service_${landingServiceOptions[index].type.name}',
              ),
              label: l10n.t(landingServiceOptions[index].type.labelKey),
              icon: landingServiceOptions[index].icon,
              selected: selected == landingServiceOptions[index].type,
              onTap: () => onSelected(landingServiceOptions[index].type),
            ),
          ),
        ],
      ],
    );
  }
}

class _ServiceSegment extends StatelessWidget {
  const _ServiceSegment({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppTokens.borderRadiusMd,
          child: Ink(
            decoration: ShapeDecoration(
              color: selected
                  ? LandingClickableStyles.selectedBackground
                  : LandingClickableStyles.background,
              shape: RoundedRectangleBorder(
                borderRadius: AppTokens.borderRadiusMd,
                side: BorderSide(
                  color: selected
                      ? LandingClickableStyles.selectedBackground
                      : LandingClickableStyles.border,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: selected
                        ? Colors.white
                        : LandingClickableStyles.icon,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : AppTokens.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../booking/models/service_type_option.dart';
import '../models/landing_service_options.dart';
import 'landing_clickable_styles.dart';

class LandingServiceCards extends StatelessWidget {
  final BookingServiceType? selectedService;
  final ValueChanged<BookingServiceType> onServiceSelected;
  final VoidCallback onBook;

  const LandingServiceCards({
    super.key,
    required this.selectedService,
    required this.onServiceSelected,
    required this.onBook,
  });

  void _onServiceTap(BookingServiceType type) {
    onServiceSelected(type);
    onBook();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppUi.sectionHeader(
            context,
            title: l10n.t('landing_services_title'),
            subtitle: l10n.t('landing_services_subtitle'),
          ),
          Row(
            key: const Key('landing_service_row'),
            children: [
              for (var index = 0; index < landingServiceOptions.length; index++) ...[
                if (index > 0) const SizedBox(width: 6),
                Expanded(
                  child: _ServiceTile(
                    key: Key(
                      'landing_service_${landingServiceOptions[index].type.name}',
                    ),
                    label: l10n.t(landingServiceOptions[index].type.labelKey),
                    icon: landingServiceOptions[index].icon,
                    iconBackground: _ServiceTile.iconBackgrounds[index],
                    iconColor: _ServiceTile.iconColors[index],
                    selected: selectedService == landingServiceOptions[index].type,
                    onTap: () => _onServiceTap(landingServiceOptions[index].type),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color iconBackground;
  final Color iconColor;
  final bool selected;
  final VoidCallback onTap;

  const _ServiceTile({
    super.key,
    required this.label,
    required this.icon,
    required this.iconBackground,
    required this.iconColor,
    required this.selected,
    required this.onTap,
  });

  static const iconBackgrounds = [
    AppTokens.primaryLight,
    AppTokens.infoLight,
    AppTokens.warningLight,
    AppTokens.successLight,
  ];

  static const iconColors = [
    AppTokens.primary,
    AppTokens.info,
    AppTokens.warning,
    AppTokens.success,
  ];

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
          hoverColor: LandingClickableStyles.hover,
          focusColor: LandingClickableStyles.hover,
          splashColor: LandingClickableStyles.pressed,
          highlightColor: LandingClickableStyles.pressed,
          borderRadius: AppTokens.borderRadiusMd,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 10,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: iconBackground,
                      shape: BoxShape.circle,
                      border: selected
                          ? Border.all(color: AppTokens.primary, width: 2)
                          : null,
                    ),
                    child: Icon(
                      icon,
                      size: 22,
                      color: iconColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                      color: selected ? AppTokens.primary : AppTokens.textPrimary,
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

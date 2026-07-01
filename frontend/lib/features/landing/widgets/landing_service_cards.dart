import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../booking/models/service_type_option.dart';

class LandingServiceCards extends StatefulWidget {
  final VoidCallback onBook;

  const LandingServiceCards({
    super.key,
    required this.onBook,
  });

  @override
  State<LandingServiceCards> createState() => _LandingServiceCardsState();
}

class _LandingServiceCardsState extends State<LandingServiceCards> {
  BookingServiceType? _selected;

  static const _services = [
    _ServiceItem(type: BookingServiceType.airportPickup, icon: Icons.flight_land),
    _ServiceItem(type: BookingServiceType.airportDropoff, icon: Icons.flight_takeoff),
    _ServiceItem(type: BookingServiceType.cityTransfer, icon: Icons.route_outlined),
    _ServiceItem(type: BookingServiceType.golfTransfer, icon: Icons.sports_golf),
  ];

  void _onServiceTap(BookingServiceType type) {
    setState(() => _selected = type);
    widget.onBook();
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
              for (var index = 0; index < _services.length; index++) ...[
                if (index > 0) const SizedBox(width: 6),
                Expanded(
                  child: _ServiceTile(
                    label: l10n.t(_services[index].type.labelKey),
                    icon: _services[index].icon,
                    selected: _selected == _services[index].type,
                    onTap: () => _onServiceTap(_services[index].type),
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
  final bool selected;
  final VoidCallback onTap;

  const _ServiceTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

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
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? AppTokens.primaryLight : AppTokens.surface,
                borderRadius: AppTokens.borderRadiusMd,
                border: Border.all(
                  color: selected ? AppTokens.primary : AppTokens.border,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 22,
                    color: selected ? AppTokens.primary : AppTokens.textSecondary,
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
                      color: selected ? AppTokens.primaryDark : AppTokens.textPrimary,
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

class _ServiceItem {
  final BookingServiceType type;
  final IconData icon;

  const _ServiceItem({required this.type, required this.icon});
}

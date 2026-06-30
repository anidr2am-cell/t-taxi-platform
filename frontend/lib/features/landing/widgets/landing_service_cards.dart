import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../booking/models/service_type_option.dart';

class LandingServiceCards extends StatelessWidget {
  final VoidCallback onBook;

  const LandingServiceCards({
    super.key,
    required this.onBook,
  });

  static const _services = [
    _ServiceItem(
      type: BookingServiceType.airportPickup,
      icon: Icons.flight_land,
      color: AppTokens.info,
    ),
    _ServiceItem(
      type: BookingServiceType.airportDropoff,
      icon: Icons.flight_takeoff,
      color: AppTokens.accent,
    ),
    _ServiceItem(
      type: BookingServiceType.cityTransfer,
      icon: Icons.location_city,
      color: AppTokens.primary,
    ),
    _ServiceItem(
      type: BookingServiceType.golfTransfer,
      icon: Icons.golf_course,
      color: AppTokens.success,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900 ? 4 : (width >= 600 ? 2 : 1);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppUi.sectionHeader(
            context,
            title: l10n.t('landing_services_title'),
            subtitle: l10n.t('landing_highlight_fixed_price'),
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: columns,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: columns == 1 ? 2.8 : 1.55,
            children: _services.map((service) {
              return AppUi.surfaceCard(
                onTap: onBook,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: service.color.withValues(alpha: 0.12),
                        borderRadius: AppTokens.borderRadiusSm,
                      ),
                      child: Icon(service.icon, color: service.color, size: 26),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.t(service.type.labelKey),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _ServiceItem {
  final BookingServiceType type;
  final IconData icon;
  final Color color;

  const _ServiceItem({
    required this.type,
    required this.icon,
    required this.color,
  });
}

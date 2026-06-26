import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
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
      color: Colors.blue,
    ),
    _ServiceItem(
      type: BookingServiceType.airportDropoff,
      icon: Icons.flight_takeoff,
      color: Colors.orange,
    ),
    _ServiceItem(
      type: BookingServiceType.cityTransfer,
      icon: Icons.location_city,
      color: Colors.green,
    ),
    _ServiceItem(
      type: BookingServiceType.golfTransfer,
      icon: Icons.golf_course,
      color: Colors.teal,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900 ? 4 : (width >= 600 ? 2 : 1);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.t('landing_services_title'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: columns,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: columns == 1 ? 2.8 : 1.6,
            children: _services.map((service) {
              return Card(
                child: InkWell(
                  onTap: onBook,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: service.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(service.icon, color: service.color, size: 28),
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
                  ),
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

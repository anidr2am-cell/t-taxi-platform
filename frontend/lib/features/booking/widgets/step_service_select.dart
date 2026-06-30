import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_ui.dart';
import '../models/service_type_option.dart';

class StepServiceSelect extends StatelessWidget {
  final BookingServiceType? selected;
  final ValueChanged<BookingServiceType> onSelected;

  const StepServiceSelect({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  IconData _iconFor(BookingServiceType type) {
    switch (type) {
      case BookingServiceType.airportPickup:
        return Icons.flight_land;
      case BookingServiceType.airportDropoff:
        return Icons.flight_takeoff;
      case BookingServiceType.cityTransfer:
        return Icons.location_city;
      case BookingServiceType.golfTransfer:
        return Icons.golf_course;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final services = BookingServiceType.values;

    return ListView.separated(
      padding: AppUi.pagePadding(context),
      itemCount: services.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final service = services[index];
        final isSelected = selected == service;
        return AppUi.selectionTile(
          title: l10n.t(service.labelKey),
          icon: _iconFor(service),
          selected: isSelected,
          onTap: () => onSelected(service),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_ui.dart';
import '../models/service_type_option.dart';
import 'wizard_compact.dart';
import 'wizard_ui.dart';

class StepServiceSelect extends StatelessWidget {
  final BookingServiceType? selected;
  final ValueChanged<BookingServiceType> onSelected;
  final bool embedded;

  const StepServiceSelect({
    super.key,
    required this.selected,
    required this.onSelected,
    this.embedded = false,
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

    final tileBuilder = (BookingServiceType service) {
      final tile = embedded
          ? WizardUi.selectionTile(
              title: l10n.t(service.labelKey),
              icon: _iconFor(service),
              selected: selected == service,
              onTap: () => onSelected(service),
            )
          : AppUi.selectionTile(
              title: l10n.t(service.labelKey),
              icon: _iconFor(service),
              selected: selected == service,
              onTap: () => onSelected(service),
            );
      return tile;
    };

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < services.length; index++) ...[
          if (index > 0)
            SizedBox(height: embedded ? WizardCompact.fieldGap : 10),
          tileBuilder(services[index]),
        ],
      ],
    );

    if (embedded) return content;

    return ListView.separated(
      padding: AppUi.pagePadding(context),
      itemCount: services.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => tileBuilder(services[index]),
    );
  }
}

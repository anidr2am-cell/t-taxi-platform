import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../models/service_type_option.dart';

class StepServiceSelect extends StatelessWidget {
  final BookingServiceType? selected;
  final ValueChanged<BookingServiceType> onSelected;

  const StepServiceSelect({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final services = BookingServiceType.values;

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: services.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final service = services[index];
        final isSelected = selected == service;
        return Card(
          color: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
          child: ListTile(
            title: Text(l10n.t(service.labelKey)),
            trailing: isSelected ? const Icon(Icons.check_circle) : null,
            onTap: () => onSelected(service),
          ),
        );
      },
    );
  }
}

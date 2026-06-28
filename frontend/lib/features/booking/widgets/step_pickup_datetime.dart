import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../controllers/booking_wizard_controller.dart';
import '../models/booking_wizard_state.dart';

class StepPickupDateTime extends StatelessWidget {
  const StepPickupDateTime({
    super.key,
    required this.state,
    required this.controller,
  });

  final BookingWizardState state;
  final BookingWizardController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selected =
        controller.selectedPickupDateTime() ??
        controller.defaultPickupDateTime();
    final min = controller.minimumPickupDateTime();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.t('pickup_datetime'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(l10n.t('pickup_minimum_notice')),
                const SizedBox(height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today),
                  title: Text(l10n.t('pickup_date')),
                  subtitle: Text(
                    state.pickupDate ?? controller.formatDate(selected),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _pickDate(context, selected, min),
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule),
                  title: Text(l10n.t('pickup_time')),
                  subtitle: Text(
                    state.pickupTime ?? controller.formatTime(selected),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _pickTime(context, selected),
                ),
                if (state.errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    state.errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickDate(
    BuildContext context,
    DateTime selected,
    DateTime min,
  ) async {
    final date = await showDatePicker(
      context: context,
      initialDate:
          DateTime(
            selected.year,
            selected.month,
            selected.day,
          ).isBefore(DateTime(min.year, min.month, min.day))
          ? DateTime(min.year, min.month, min.day)
          : DateTime(selected.year, selected.month, selected.day),
      firstDate: DateTime(min.year, min.month, min.day),
      lastDate: DateTime(min.year + 2),
    );
    if (date == null) return;
    await controller.setPickupDateTime(
      DateTime(date.year, date.month, date.day, selected.hour, selected.minute),
    );
  }

  Future<void> _pickTime(BuildContext context, DateTime selected) async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: selected.hour, minute: selected.minute),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (time == null) return;
    await controller.setPickupDateTime(
      DateTime(
        selected.year,
        selected.month,
        selected.day,
        time.hour,
        time.minute,
      ),
    );
  }
}

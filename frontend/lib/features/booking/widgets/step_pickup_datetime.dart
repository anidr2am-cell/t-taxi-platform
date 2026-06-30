import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
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
      padding: AppUi.pagePadding(context),
      children: [
        AppUi.sectionHeader(
          context,
          title: l10n.t('pickup_datetime'),
          subtitle: l10n.t('pickup_minimum_notice'),
        ),
        AppUi.surfaceCard(
          child: Column(
            children: [
              _PickerRow(
                icon: Icons.calendar_today_outlined,
                title: l10n.t('pickup_date'),
                value: state.pickupDate ?? controller.formatDate(selected),
                onTap: () => _pickDate(context, selected, min),
              ),
              const Divider(height: 1),
              _PickerRow(
                icon: Icons.schedule_outlined,
                title: l10n.t('pickup_time'),
                value: state.pickupTime ?? controller.formatTime(selected),
                onTap: () => _pickTime(context, selected),
              ),
            ],
          ),
        ),
        if (state.errorMessage != null) ...[
          const SizedBox(height: AppTokens.spaceMd),
          AppUi.errorState(message: state.errorMessage!),
        ],
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

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppTokens.borderRadiusMd,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTokens.primary.withValues(alpha: 0.1),
                borderRadius: AppTokens.borderRadiusSm,
              ),
              child: Icon(icon, color: AppTokens.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppTokens.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppTokens.textMuted),
          ],
        ),
      ),
    );
  }
}

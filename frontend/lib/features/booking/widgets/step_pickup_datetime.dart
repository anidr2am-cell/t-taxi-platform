import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../controllers/booking_wizard_controller.dart';
import '../models/booking_wizard_state.dart';
import '../models/service_type_option.dart';
import 'wizard_compact.dart';

class StepPickupDateTime extends StatefulWidget {
  const StepPickupDateTime({
    super.key,
    required this.state,
    required this.controller,
    this.onFlightNumberChanged,
    this.embedded = false,
    this.focusNode,
  });

  final BookingWizardState state;
  final BookingWizardController controller;
  final ValueChanged<String>? onFlightNumberChanged;
  final bool embedded;
  final FocusNode? focusNode;

  @override
  State<StepPickupDateTime> createState() => _StepPickupDateTimeState();
}

class _StepPickupDateTimeState extends State<StepPickupDateTime> {
  late final TextEditingController _flightController;

  @override
  void initState() {
    super.initState();
    _flightController = TextEditingController(text: widget.state.flightNumber);
  }

  @override
  void didUpdateWidget(covariant StepPickupDateTime oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.flightNumber != widget.state.flightNumber &&
        _flightController.text != widget.state.flightNumber) {
      _flightController.text = widget.state.flightNumber;
    }
  }

  @override
  void dispose() {
    _flightController.dispose();
    super.dispose();
  }

  bool get _showFlightField =>
      widget.state.serviceType == BookingServiceType.airportPickup &&
      widget.onFlightNumberChanged != null;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selected =
        widget.controller.selectedPickupDateTime() ??
        widget.controller.defaultPickupDateTime();
    final min = widget.controller.minimumPickupDateTime();

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embedded)
          AppUi.sectionHeader(
            context,
            title: l10n.t('pickup_datetime'),
            subtitle: l10n.t('pickup_minimum_notice'),
          ),
        if (widget.embedded)
          Text(
            l10n.t('pickup_minimum_notice'),
            style: WizardCompact.hintTextStyle,
          ),
        if (widget.embedded) const SizedBox(height: WizardCompact.fieldGap),
        LayoutBuilder(
          builder: (context, constraints) {
            final dateTimeCard = AppUi.surfaceCard(
              padding: widget.embedded
                  ? const EdgeInsets.symmetric(
                      horizontal: WizardCompact.cardPadding,
                      vertical: 2,
                    )
                  : const EdgeInsets.all(AppTokens.spaceMd),
              child: Column(
                children: [
                  _PickerRow(
                    compact: widget.embedded,
                    icon: Icons.calendar_today_outlined,
                    title: l10n.t('pickup_date'),
                    value: widget.state.pickupDate ??
                        widget.controller.formatDate(selected),
                    onTap: () => _pickDate(context, selected, min),
                  ),
                  const Divider(height: 1),
                  _PickerRow(
                    compact: widget.embedded,
                    icon: Icons.schedule_outlined,
                    title: l10n.t('pickup_time'),
                    value: widget.state.pickupTime ??
                        widget.controller.formatTime(selected),
                    onTap: () => _pickTime(context, selected),
                  ),
                ],
              ),
            );

            if (!_showFlightField) {
              return Focus(
                focusNode: widget.focusNode,
                child: dateTimeCard,
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                dateTimeCard,
                const SizedBox(height: WizardCompact.fieldGap),
                TextField(
                  controller: _flightController,
                  focusNode: widget.focusNode,
                  decoration: WizardCompact.inputDecoration(
                    label: l10n.t('flight_number'),
                    hint: l10n.t('flight_number_hint'),
                    prefixIcon: const Icon(Icons.flight_outlined, size: 20),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  onChanged: widget.onFlightNumberChanged,
                ),
              ],
            );
          },
        ),
        if (!widget.embedded && widget.state.errorMessage != null) ...[
          const SizedBox(height: AppTokens.spaceMd),
          AppUi.errorState(message: l10n.t(widget.state.errorMessage!)),
        ],
      ],
    );

    if (widget.embedded) return content;

    return ListView(
      padding: AppUi.pagePadding(context),
      children: [content],
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
    await widget.controller.setPickupDateTime(
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
    await widget.controller.setPickupDateTime(
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
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final verticalPadding = compact ? 10.0 : 14.0;
    return Semantics(
      button: true,
      label: title,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppTokens.borderRadiusMd,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: WizardCompact.minTouchHeight),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: verticalPadding, horizontal: 4),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(compact ? 8 : 10),
                  decoration: BoxDecoration(
                    color: AppTokens.primary.withValues(alpha: 0.1),
                    borderRadius: AppTokens.borderRadiusSm,
                  ),
                  child: Icon(icon, color: AppTokens.primary, size: compact ? 20 : 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: AppTokens.textSecondary,
                          fontSize: compact ? 12 : 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        value,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: compact ? 15 : 16,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppTokens.textMuted, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

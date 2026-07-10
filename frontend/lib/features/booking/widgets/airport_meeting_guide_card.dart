import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';

class AirportMeetingVehicleInfo {
  const AirportMeetingVehicleInfo({
    this.driverName,
    this.driverPhone,
    this.vehicleType,
    this.vehicleColor,
    this.vehiclePlateNumber,
  });

  final String? driverName;
  final String? driverPhone;
  final String? vehicleType;
  final String? vehicleColor;
  final String? vehiclePlateNumber;

  bool get hasAssignedDetails =>
      _hasText(driverName) ||
      _hasText(driverPhone) ||
      _hasText(vehiclePlateNumber);

  static bool _hasText(String? value) =>
      value != null && value.trim().isNotEmpty;
}

class AirportMeetingGuideCard extends StatelessWidget {
  const AirportMeetingGuideCard({
    super.key,
    required this.serviceTypeCode,
    required this.originAirportCode,
    required this.nameSignRequested,
    this.vehicleInfo,
    this.onNotifyPickup,
    this.pickupAlertSent = false,
  });

  final String? serviceTypeCode;
  final String? originAirportCode;
  final bool nameSignRequested;
  final AirportMeetingVehicleInfo? vehicleInfo;
  final Future<void> Function()? onNotifyPickup;
  final bool pickupAlertSent;

  static bool shouldShow({
    required String? serviceTypeCode,
    required String? originAirportCode,
  }) {
    return serviceTypeCode?.toUpperCase() == 'AIRPORT_PICKUP' &&
        originAirportCode?.toUpperCase() == 'BKK';
  }

  @override
  Widget build(BuildContext context) {
    if (!shouldShow(
      serviceTypeCode: serviceTypeCode,
      originAirportCode: originAirportCode,
    )) {
      return const SizedBox.shrink();
    }

    final l10n = context.l10n;
    final gateNumber = nameSignRequested ? '3' : '7';
    final titleKey = nameSignRequested
        ? 'airport_meeting_gate_3_title'
        : 'airport_meeting_gate_7_title';
    final highlightKey = nameSignRequested
        ? 'airport_meeting_picket_highlight'
        : 'airport_meeting_no_picket_highlight';
    final bodyKeys = nameSignRequested
        ? ['airport_meeting_picket_body_1', 'airport_meeting_picket_body_2']
        : [
            'airport_meeting_no_picket_body_1',
            'airport_meeting_no_picket_body_2',
          ];
    final stepKeys = nameSignRequested
        ? [
            'airport_meeting_step_luggage',
            'airport_meeting_step_gate_3',
            'airport_meeting_step_find_picket',
            'airport_meeting_step_wait_staff',
            'airport_meeting_step_board_after_staff',
          ]
        : [
            'airport_meeting_step_luggage',
            'airport_meeting_step_notify_driver',
            'airport_meeting_step_vehicle_number',
            'airport_meeting_step_gate_7',
            'airport_meeting_step_board',
          ];

    return Semantics(
      label: l10n
          .t('airport_meeting_semantics')
          .replaceAll('{gate}', gateNumber),
      child: AppUi.surfaceCard(
        backgroundColor: AppTokens.primaryLight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              title: l10n.t(titleKey),
              gateNumber: gateNumber,
              gateLabel: l10n.t(
                nameSignRequested
                    ? 'airport_meeting_gate_inside'
                    : 'airport_meeting_gate_outside',
              ),
            ),
            const SizedBox(height: AppTokens.spaceMd),
            _Highlight(text: l10n.t(highlightKey)),
            const SizedBox(height: AppTokens.spaceMd),
            for (final key in bodyKeys) ...[
              Text(
                l10n.t(key),
                style: const TextStyle(
                  color: AppTokens.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: AppTokens.spaceSm),
            ],
            if (nameSignRequested) ...[
              _InfoNotice(
                icon: Icons.door_front_door_outlined,
                text: l10n.t('airport_meeting_do_not_exit'),
              ),
              const SizedBox(height: AppTokens.spaceMd),
            ],
            _Steps(
              stepKeys: stepKeys,
              emphasizedStepIndex: nameSignRequested ? null : 1,
            ),
            const SizedBox(height: AppTokens.spaceMd),
            _VehicleBlock(info: vehicleInfo),
            const SizedBox(height: AppTokens.spaceMd),
            _PickupNotificationAction(
              onNotifyPickup: onNotifyPickup,
              pickupAlertSent: pickupAlertSent,
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.gateNumber,
    required this.gateLabel,
  });

  final String title;
  final String gateNumber;
  final String gateLabel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        return Wrap(
          spacing: AppTokens.spaceMd,
          runSpacing: AppTokens.spaceSm,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            SizedBox(
              width: compact
                  ? constraints.maxWidth
                  : constraints.maxWidth - 136,
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppTokens.primaryDark,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _GateBadge(number: gateNumber, label: gateLabel),
          ],
        );
      },
    );
  }
}

class _GateBadge extends StatelessWidget {
  const _GateBadge({required this.number, required this.label});

  final String number;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 44, minWidth: 112),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: AppTokens.borderRadiusMd,
        border: Border.all(color: AppTokens.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            number,
            style: const TextStyle(
              color: AppTokens.accent,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: AppTokens.primaryDark,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Highlight extends StatelessWidget {
  const _Highlight({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTokens.accentLight,
        borderRadius: AppTokens.borderRadiusMd,
        border: Border.all(color: AppTokens.accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: AppTokens.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppTokens.textPrimary,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.stepKeys, this.emphasizedStepIndex});

  final List<String> stepKeys;
  final int? emphasizedStepIndex;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        for (var i = 0; i < stepKeys.length; i++)
          Builder(
            builder: (context) {
              final isEmphasized = i == emphasizedStepIndex;
              return Padding(
                padding: EdgeInsets.only(
                  bottom: i == stepKeys.length - 1 ? 0 : 10,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isEmphasized
                            ? AppTokens.accent
                            : AppTokens.primaryDark,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          color: AppTokens.surface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          l10n.t(stepKeys[i]),
                          style: TextStyle(
                            color: isEmphasized
                                ? AppTokens.error
                                : AppTokens.textPrimary,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

class _PickupNotificationAction extends StatefulWidget {
  const _PickupNotificationAction({
    required this.onNotifyPickup,
    required this.pickupAlertSent,
  });

  final Future<void> Function()? onNotifyPickup;
  final bool pickupAlertSent;

  @override
  State<_PickupNotificationAction> createState() =>
      _PickupNotificationActionState();
}

class _PickupNotificationActionState extends State<_PickupNotificationAction> {
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sent = widget.pickupAlertSent;
  }

  @override
  void didUpdateWidget(covariant _PickupNotificationAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pickupAlertSent && !_sent) {
      _sent = true;
    }
  }

  Future<void> _send() async {
    if (_sending || widget.onNotifyPickup == null) return;
    if (_sent) {
      await widget.onNotifyPickup!();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.t('airport_meeting_notify_confirm_title')),
        content: Text(context.l10n.t('airport_meeting_notify_confirm_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.t('airport_meeting_notify_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.t('airport_meeting_notify_confirm_send')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.onNotifyPickup!();
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sent = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = context.l10n.t('airport_meeting_notify_failed');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (widget.onNotifyPickup == null) {
      return _InfoNotice(
        icon: Icons.chat_bubble_outline,
        text: l10n.t('airport_meeting_notify_waiting_driver'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InfoNotice(
          icon: Icons.luggage_outlined,
          text: l10n.t('airport_meeting_notify_luggage_first'),
        ),
        const SizedBox(height: AppTokens.spaceSm),
        SizedBox(
          width: double.infinity,
          child: AppUi.primaryButton(
            label: _sent
                ? l10n.t('airport_meeting_message_driver')
                : l10n.t('airport_meeting_notify_button'),
            icon: _sent
                ? Icons.chat_bubble_outline
                : Icons.notifications_active,
            loading: _sending,
            onPressed: _sending ? null : _send,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppTokens.spaceSm),
          Text(
            _error!,
            style: const TextStyle(
              color: AppTokens.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _VehicleBlock extends StatelessWidget {
  const _VehicleBlock({required this.info});

  final AirportMeetingVehicleInfo? info;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final vehicle = info;
    if (vehicle == null || !vehicle.hasAssignedDetails) {
      return _InfoNotice(
        icon: Icons.directions_car_filled_outlined,
        text: l10n.t('airport_meeting_vehicle_pending'),
      );
    }

    final rows = <MapEntry<String, String>>[
      if (_hasText(vehicle.driverName))
        MapEntry(l10n.t('airport_meeting_driver'), vehicle.driverName!.trim()),
      if (_hasText(vehicle.driverPhone))
        MapEntry(
          l10n.t('airport_meeting_driver_phone'),
          vehicle.driverPhone!.trim(),
        ),
      if (_hasText(vehicle.vehicleType))
        MapEntry(
          l10n.t('airport_meeting_vehicle_type'),
          vehicle.vehicleType!.trim(),
        ),
      if (_hasText(vehicle.vehicleColor))
        MapEntry(
          l10n.t('airport_meeting_vehicle_color'),
          vehicle.vehicleColor!.trim(),
        ),
      if (_hasText(vehicle.vehiclePlateNumber))
        MapEntry(
          l10n.t('airport_meeting_vehicle_plate'),
          vehicle.vehiclePlateNumber!.trim(),
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: AppTokens.borderRadiusMd,
        border: Border.all(color: AppTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.t('airport_meeting_vehicle_info'),
            style: const TextStyle(
              color: AppTokens.primaryDark,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          for (final row in rows)
            AppUi.summaryRow(label: row.key, value: row.value),
        ],
      ),
    );
  }

  static bool _hasText(String? value) =>
      value != null && value.trim().isNotEmpty;
}

class _InfoNotice extends StatelessWidget {
  const _InfoNotice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTokens.surface.withValues(alpha: 0.82),
        borderRadius: AppTokens.borderRadiusMd,
        border: Border.all(color: AppTokens.primary.withValues(alpha: 0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTokens.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppTokens.textSecondary,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

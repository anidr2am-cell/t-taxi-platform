import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../driver_trip_contact.dart';
import '../driver_ux.dart';
import '../models/driver_booking.dart';

class DriverTodayCurrentTripCard extends StatelessWidget {
  const DriverTodayCurrentTripCard({
    super.key,
    required this.booking,
    required this.onOpenPrimary,
    this.customerPhone,
    this.settlement,
  });

  final DriverBooking booking;
  final VoidCallback onOpenPrimary;
  final String? customerPhone;
  final Map<String, dynamic>? settlement;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final guidanceKey = DriverUx.statusGuidanceKey(booking.status);
    final navigateAddress = DriverUx.navigateTargetAddress(booking);
    final canNavigate = DriverTripContact.hasNavigableAddress(navigateAddress);
    final canContact = DriverUx.canContactCustomer(booking.status);
    final phone = canContact ? customerPhone ?? booking.customerPhone : null;
    final canCall = DriverTripContact.hasCallablePhone(phone);
    final luggageCount = _luggageCount(booking);

    return AppUi.surfaceCard(
      backgroundColor: AppTokens.primaryLight,
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.t('driver_today_current_trip'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppTokens.primaryDark,
                  ),
                ),
              ),
              AppUi.statusBadge(
                l10n.t(DriverUx.statusLabelKey(booking.status)),
                tone: AppUi.toneForBookingStatus(booking.status),
              ),
            ],
          ),
          if (guidanceKey != null) ...[
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              l10n.t(guidanceKey),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: AppTokens.spaceMd),
          Row(
            children: [
              const Icon(Icons.schedule, size: 18, color: AppTokens.primary),
              const SizedBox(width: 6),
              Text(
                booking.pickupTime,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceSm),
          _RouteLine(origin: booking.origin, destination: booking.destination),
          const SizedBox(height: AppTokens.spaceSm),
          Wrap(
            spacing: AppTokens.spaceSm,
            runSpacing: 4,
            children: [
              if (booking.customerDisplayName != null)
                _MetaChip(
                  icon: Icons.person_outline,
                  label: booking.customerDisplayName!,
                ),
              _MetaChip(
                icon: Icons.people_outline,
                label:
                    '${booking.passengerCount} ${l10n.t('driver_passengers')}',
              ),
              if (luggageCount > 0)
                _MetaChip(
                  icon: Icons.luggage_outlined,
                  label: '$luggageCount ${l10n.t('driver_detail_luggage')}',
                ),
              _MetaChip(
                icon: Icons.directions_car_outlined,
                label: booking.vehicleTypeName,
              ),
              if (booking.nameSignRequested)
                _MetaChip(
                  icon: Icons.badge_outlined,
                  label: l10n.t('driver_name_sign_required'),
                ),
            ],
          ),
          if (booking.flightNumber != null) ...[
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              '${l10n.t('driver_detail_flight_number')}: ${booking.flightNumber}',
              style: const TextStyle(
                color: AppTokens.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: AppTokens.spaceSm),
          Text(
            booking.bookingNumber,
            style: const TextStyle(color: AppTokens.textMuted, fontSize: 12),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          Row(
            children: [
              Expanded(
                child: _QuickActionButton(
                  icon: Icons.navigation_outlined,
                  label: l10n.t('driver_quick_navigate'),
                  enabled: canNavigate,
                  onPressed: canNavigate
                      ? () => DriverTripContact.openMaps(navigateAddress)
                      : null,
                ),
              ),
              if (canContact) ...[
                const SizedBox(width: AppTokens.spaceSm),
                Expanded(
                  child: _QuickActionButton(
                    icon: Icons.phone_outlined,
                    label: l10n.t('driver_call_customer'),
                    enabled: canCall,
                    onPressed: canCall && phone != null
                        ? () => DriverTripContact.callPhone(phone)
                        : null,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppTokens.spaceMd),
          SizedBox(
            height: 52,
            width: double.infinity,
            child: FilledButton(
              onPressed: onOpenPrimary,
              child: Text(
                l10n.t(
                  DriverUx.todayPrimaryCtaKey(booking, settlement: settlement),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _luggageCount(DriverBooking booking) {
    final luggage = booking.luggage;
    if (luggage == null) return 0;
    return [
      luggage['carriers20Inch'],
      luggage['carriers24InchPlus'],
      luggage['golfBags'],
    ].fold<int>(0, (sum, value) => sum + ((value as num?)?.toInt() ?? 0));
  }
}

class DriverTodayTripListTile extends StatelessWidget {
  const DriverTodayTripListTile({
    super.key,
    required this.booking,
    required this.onTap,
  });

  final DriverBooking booking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppUi.surfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                booking.pickupTime,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              AppUi.statusBadge(
                l10n.t(DriverUx.statusLabelKey(booking.status)),
                tone: AppUi.toneForBookingStatus(booking.status),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _RouteLine(
            origin: booking.origin,
            destination: booking.destination,
            compact: true,
          ),
          if (booking.customerDisplayName != null) ...[
            const SizedBox(height: 6),
            Text(
              booking.customerDisplayName!,
              style: const TextStyle(color: AppTokens.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _RouteLine extends StatelessWidget {
  const _RouteLine({
    required this.origin,
    required this.destination,
    this.compact = false,
  });

  final String origin;
  final String destination;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: compact ? 14 : 15,
      fontWeight: compact ? FontWeight.w500 : FontWeight.w600,
      height: 1.35,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          origin,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              const Icon(
                Icons.arrow_downward,
                size: 14,
                color: AppTokens.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                '→',
                style: TextStyle(
                  color: AppTokens.textMuted,
                  fontSize: compact ? 13 : 14,
                ),
              ),
            ],
          ),
        ),
        Text(
          destination,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: style.copyWith(color: AppTokens.textSecondary),
        ),
      ],
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.enabled,
    this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: OutlinedButton(
        onPressed: enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            vertical: AppTokens.spaceSm,
            horizontal: 4,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, height: 1.2),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTokens.textSecondary),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: AppTokens.textSecondary),
        ),
      ],
    );
  }
}

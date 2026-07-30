import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../driver_today_trip_formatters.dart';
import '../driver_trip_contact.dart';
import '../driver_ux.dart';
import '../models/driver_booking.dart';

class _DriverTodayRouteEndpoint extends StatelessWidget {
  const _DriverTodayRouteEndpoint({
    required this.prefix,
    required this.location,
    required this.fallbackAddress,
    this.compact = false,
  });

  final String prefix;
  final DriverBookingLocation? location;
  final String fallbackAddress;
  final bool compact;

  static const _highlightColor = Color(0xFF006A60);

  @override
  Widget build(BuildContext context) {
    final resolved = location ??
        (fallbackAddress.trim().isNotEmpty
            ? DriverBookingLocation(address: fallbackAddress)
            : null);
    final nameTh = resolved?.nameTh?.trim();
    final name = resolved?.name?.trim();
    final displayName = (nameTh != null && nameTh.isNotEmpty)
        ? nameTh
        : (name != null && name.isNotEmpty
            ? name
            : (resolved != null
                ? DriverTripContact.displayLabelFor(resolved)
                : null));
    final hasStructuredName =
        (nameTh != null && nameTh.isNotEmpty) ||
        (name != null && name.isNotEmpty);
    final address = resolved?.secondaryAddress ??
        (hasStructuredName ? null : fallbackAddress.trim());
    final showAddress = address != null &&
        address.isNotEmpty &&
        address != displayName;
    final labelStyle = TextStyle(
      fontSize: compact ? 14 : 15,
      color: AppTokens.textSecondary,
      height: 1.35,
    );
    final nameStyle = TextStyle(
      fontSize: compact ? 14 : 15,
      fontWeight: FontWeight.w700,
      color: _highlightColor,
      height: 1.35,
    );

    if (displayName == null || displayName.isEmpty) {
      return Text(
        '$prefix - ${fallbackAddress.trim().isEmpty ? '위치 정보 없음' : fallbackAddress.trim()}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: labelStyle,
      );
    }

    if (!hasStructuredName) {
      return Text(
        '$prefix - $displayName',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: nameStyle,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '$prefix - ', style: labelStyle),
              TextSpan(text: displayName, style: nameStyle),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (showAddress) ...[
          const SizedBox(height: 2),
          Text(
            address,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 13 : 14,
              height: 1.35,
              color: compact ? AppTokens.textSecondary : null,
            ),
          ),
        ],
      ],
    );
  }
}

class DriverTodayCurrentTripCard extends StatelessWidget {
  const DriverTodayCurrentTripCard({
    super.key,
    required this.booking,
    required this.onOpenPrimary,
    this.settlement,
  });

  final DriverBooking booking;
  final VoidCallback onOpenPrimary;
  final Map<String, dynamic>? settlement;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final guidanceKey = DriverUx.statusGuidanceKey(booking.status);
    final navigateLocation = DriverUx.navigateTargetLocation(booking);
    final canNavigate = DriverTripContact.hasNavigableLocation(navigateLocation);
    final luggageCount = _luggageCount(booking);
    final pickupRequestTime = formatDriverPickupRequestTime(
      pickupDate: booking.pickupDate,
      pickupTime: booking.pickupTime,
    );

    return AppUi.surfaceCard(
      backgroundColor: AppTokens.primaryLight,
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: AppUi.statusBadge(
              l10n.t(DriverUx.statusLabelKey(booking.status)),
              tone: AppUi.toneForBookingStatus(booking.status),
            ),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.schedule, size: 18, color: AppTokens.primary),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  pickupRequestTime,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceSm),
          _RouteLine(
            origin: _DriverTodayRouteEndpoint(
              prefix: '출발지',
              location: booking.pickupLocation,
              fallbackAddress: booking.origin,
            ),
            destination: _DriverTodayRouteEndpoint(
              prefix: '도착지',
              location: booking.destinationLocation,
              fallbackAddress: booking.destination,
            ),
          ),
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
          SizedBox(
            width: double.infinity,
            child: _QuickActionButton(
              icon: Icons.navigation_outlined,
              label: l10n.t('driver_quick_navigate'),
              enabled: canNavigate,
              onPressed: canNavigate
                  ? () => DriverTripContact.openMapsForLocation(navigateLocation)
                  : null,
            ),
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
            origin: _DriverTodayRouteEndpoint(
              prefix: '출발지',
              location: booking.pickupLocation,
              fallbackAddress: booking.origin,
              compact: true,
            ),
            destination: _DriverTodayRouteEndpoint(
              prefix: '도착지',
              location: booking.destinationLocation,
              fallbackAddress: booking.destination,
              compact: true,
            ),
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

  final Widget origin;
  final Widget destination;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        origin,
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
        destination,
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

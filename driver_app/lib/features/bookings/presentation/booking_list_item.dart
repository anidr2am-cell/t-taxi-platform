import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../data/booking_models.dart';
import 'booking_display_formatters.dart';
import 'booking_meeting_gate.dart';
import 'booking_status_label.dart';
import 'pickup_schedule.dart';
import 'release_assignment_ui.dart';

class BookingListItem extends StatelessWidget {
  const BookingListItem({
    super.key,
    required this.booking,
    required this.onTap,
    this.capabilities,
    this.now,
    this.releaseBusy = false,
    this.onReleasePressed,
  });

  final BookingSummary booking;
  final VoidCallback onTap;
  final BookingCapabilities? capabilities;
  final DateTime? now;
  final bool releaseBusy;
  final VoidCallback? onReleasePressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final vehicle = booking.vehicleType.name.isNotEmpty
        ? booking.vehicleType.name
        : booking.vehicleType.code;
    final scheduledPickup = formatBookingDateTime(booking.scheduledPickupAt);
    final standbyReference = formatBookingDateTime(
      booking.standbyReferenceTime,
    );
    final meetingGate = resolveBkkAirportPickupMeetingGate(
      serviceTypeCode: booking.serviceType.code,
      nameSignRequested: booking.nameSignRequested,
      pickupCandidates: [
        booking.pickupLocation.name,
        booking.pickupLocation.address,
        booking.origin,
      ],
    );
    final releaseUi = capabilities == null
        ? null
        : ReleaseAssignmentUiState.evaluate(
            booking: booking,
            capabilities: capabilities!,
            now: now ?? DateTime.now(),
          );
    final pickupDelay = pickupDelayInfo(
      scheduledPickupAt: booking.scheduledPickupAt,
      pickupDate: booking.pickupDate,
      pickupTime: booking.pickupTime,
      now: () => now ?? DateTime.now(),
    );
    final pickupDelayMessage = pickupDelay == null
        ? null
        : pickupDelayBannerMessage(l10n, pickupDelay);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pickupDelayMessage case final message?)
            MaterialBanner(
              key: Key('pickupDelayBanner-${booking.bookingNumber}'),
              content: Text(message),
              leading: const Icon(Icons.info_outline),
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
              actions: const [SizedBox.shrink()],
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: Theme.of(context).textTheme.titleMedium,
                      children: [
                        TextSpan(
                          text: '출발 요청시간 : ',
                          style: TextStyle(
                            fontWeight: FontWeight.normal,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                        TextSpan(
                          text: scheduledPickup ?? l10n.noTripScheduleInfo,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                if (releaseUi != null)
                  ReleaseAssignmentListButton(
                    bookingNumber: booking.bookingNumber,
                    uiState: releaseUi,
                    busy: releaseBusy,
                    onPressed: onReleasePressed,
                  ),
                BookingStatusLabel(status: booking.status),
              ],
            ),
          ),
          InkWell(
            key: Key('booking-${booking.bookingNumber}'),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (meetingGate != null) ...[
                    Align(
                      alignment: Alignment.centerRight,
                      child: Chip(
                        key: Key('bookingGate-${booking.bookingNumber}'),
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(Icons.meeting_room_outlined, size: 16),
                        label: Text(l10n.meetingGateNumber(int.parse(meetingGate))),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    booking.bookingNumber,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  _RouteLine(
                    icon: Icons.trip_origin,
                    label: '출발지',
                    location: booking.pickupLocation,
                  ),
                  const SizedBox(height: 8),
                  _RouteLine(
                    icon: Icons.location_on_outlined,
                    label: '도착지',
                    location: booking.destinationLocation,
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    children: [
                      if (booking.customerDisplayName case final name?)
                        _Fact(icon: Icons.person_outline, text: name),
                      if (vehicle.isNotEmpty)
                        _Fact(icon: Icons.local_taxi_outlined, text: vehicle),
                      if (booking.flightNumber case final flight?)
                        _Fact(icon: Icons.flight_outlined, text: flight),
                      if (standbyReference != null)
                        _Fact(
                          icon: Icons.schedule_outlined,
                          text: l10n.standbyReferenceLabel(standbyReference),
                        ),
                      if (booking.driverExpectedIncome.isAvailable)
                        _Fact(
                          icon: Icons.payments_outlined,
                          text: l10n.expectedIncomeLabel(
                            formatMoneyLocalized(
                              l10n,
                              booking.driverExpectedIncome,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteLine extends StatelessWidget {
  const _RouteLine({
    required this.icon,
    required this.label,
    required this.location,
  });

  final IconData icon;
  final String label;
  final BookingLocation location;

  static const _highlightColor = Color(0xFF006A60);

  @override
  Widget build(BuildContext context) {
    final lines = parseBookingLocation(location);
    final labelStyle = TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

    if (!lines.hasPlaceName) {
      final address = lines.hasAddressLine ? lines.addressLine! : '';
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '$label : ', style: labelStyle),
                  if (address.isNotEmpty) TextSpan(text: address),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '$label : ', style: labelStyle),
                    TextSpan(
                      text: lines.placeName!,
                      style: const TextStyle(
                        color: _highlightColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (lines.hasSeparateAddress) ...[
                const SizedBox(height: 2),
                Text(lines.addressLine!),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [Icon(icon, size: 16), const SizedBox(width: 5), Text(text)],
  );
}

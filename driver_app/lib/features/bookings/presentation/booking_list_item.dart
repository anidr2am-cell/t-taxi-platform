import 'package:flutter/material.dart';

import '../data/booking_models.dart';
import 'booking_display_formatters.dart';
import 'booking_meeting_gate.dart';
import 'booking_status_label.dart';
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
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    scheduledPickup ?? '운행 시각 정보 없음',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
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
                        label: Text('$meetingGate번 게이트'),
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
                    text: formatBookingLocation(booking.pickupLocation),
                  ),
                  const SizedBox(height: 8),
                  _RouteLine(
                    icon: Icons.location_on_outlined,
                    text: formatBookingLocation(booking.destinationLocation),
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
                          text: '대기 기준 $standbyReference',
                        ),
                      if (booking.driverExpectedIncome.isAvailable)
                        _Fact(
                          icon: Icons.payments_outlined,
                          text:
                              '예상 수입 ${formatMoney(booking.driverExpectedIncome)}',
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
  const _RouteLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18),
      const SizedBox(width: 8),
      Expanded(child: Text(text)),
    ],
  );
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

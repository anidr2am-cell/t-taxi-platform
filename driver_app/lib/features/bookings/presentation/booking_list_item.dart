import 'package:flutter/material.dart';

import '../data/booking_models.dart';
import 'booking_status_label.dart';

class BookingListItem extends StatelessWidget {
  const BookingListItem({
    super.key,
    required this.booking,
    required this.onTap,
  });

  final BookingSummary booking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vehicle = booking.vehicleType.name.isNotEmpty
        ? booking.vehicleType.name
        : booking.vehicleType.code;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('booking-${booking.bookingNumber}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${booking.pickupDate}  ${booking.pickupTime}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  BookingStatusLabel(status: booking.status),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                booking.bookingNumber,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              _RouteLine(icon: Icons.trip_origin, text: booking.origin),
              const SizedBox(height: 8),
              _RouteLine(
                icon: Icons.location_on_outlined,
                text: booking.destination,
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

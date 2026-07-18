import 'package:flutter/material.dart';

import '../data/booking_models.dart';

class BookingStatusLabel extends StatelessWidget {
  const BookingStatusLabel({super.key, required this.status});

  final BookingStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = switch (status.code) {
      BookingStatusCode.cancelled || BookingStatusCode.noShow => (
        Theme.of(context).colorScheme.errorContainer,
        Theme.of(context).colorScheme.onErrorContainer,
      ),
      BookingStatusCode.completed => (
        Theme.of(context).colorScheme.secondaryContainer,
        Theme.of(context).colorScheme.onSecondaryContainer,
      ),
      _ => (
        Theme.of(context).colorScheme.primaryContainer,
        Theme.of(context).colorScheme.onPrimaryContainer,
      ),
    };
    return Semantics(
      label: '예약 상태 ${status.label}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.$1,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            status.label,
            style: TextStyle(
              color: colors.$2,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

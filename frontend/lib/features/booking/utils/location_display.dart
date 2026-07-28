import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';
import '../models/location_option.dart';

typedef BookingLocationParts = ({String? primaryName, String? secondaryAddress});

BookingLocationParts resolveBookingLocationParts({
  String? name,
  String? address,
  String? fallbackDisplayName,
}) {
  final trimmedAddress = address?.trim();
  final trimmedName = _firstNonEmpty([name, fallbackDisplayName]);

  if (trimmedAddress == null || trimmedAddress.isEmpty) {
    return (primaryName: trimmedName, secondaryAddress: null);
  }
  if (trimmedName == null || trimmedName.isEmpty) {
    return (primaryName: null, secondaryAddress: trimmedAddress);
  }
  if (trimmedName == trimmedAddress) {
    return (primaryName: null, secondaryAddress: trimmedAddress);
  }
  return (primaryName: trimmedName, secondaryAddress: trimmedAddress);
}

BookingLocationParts resolveLocationOptionParts(LocationOption? location) {
  if (location == null) {
    return (primaryName: null, secondaryAddress: null);
  }
  return resolveBookingLocationParts(
    name: location.name,
    address: location.address,
    fallbackDisplayName: location.displayName,
  );
}

class BookingLocationDisplay extends StatelessWidget {
  const BookingLocationDisplay({
    super.key,
    this.name,
    this.address,
    this.fallbackDisplayName,
    this.emphasizeName = false,
    this.emptyPlaceholder = '-',
  });

  final String? name;
  final String? address;
  final String? fallbackDisplayName;
  final bool emphasizeName;
  final String emptyPlaceholder;

  factory BookingLocationDisplay.fromLocationOption(
    LocationOption? location, {
    Key? key,
    bool emphasizeName = false,
    String emptyPlaceholder = '-',
  }) {
    final parts = resolveLocationOptionParts(location);
    return BookingLocationDisplay(
      key: key,
      name: parts.primaryName,
      address: parts.secondaryAddress,
      emphasizeName: emphasizeName,
      emptyPlaceholder: emptyPlaceholder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final parts = resolveBookingLocationParts(
      name: name,
      address: address,
      fallbackDisplayName: fallbackDisplayName,
    );
    final primary = parts.primaryName;
    final secondary = parts.secondaryAddress;

    if (primary == null && (secondary == null || secondary.isEmpty)) {
      return Text(
        emptyPlaceholder,
        style: _valueStyle(emphasize: emphasizeName),
      );
    }

    if (primary == null) {
      return Text(secondary!, style: _valueStyle(emphasize: emphasizeName));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          primary,
          style: _valueStyle(emphasize: true),
        ),
        if (secondary != null && secondary.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            secondary,
            style: const TextStyle(
              fontSize: 13,
              height: 1.35,
              color: AppTokens.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  TextStyle _valueStyle({required bool emphasize}) {
    return TextStyle(
      fontSize: emphasize ? 16 : 14,
      fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
      color: emphasize ? AppTokens.primaryDark : AppTokens.textPrimary,
      height: 1.35,
    );
  }
}

Widget bookingLocationSummaryRow({
  required String label,
  String? name,
  String? address,
  String? fallbackDisplayName,
  bool emphasize = false,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: const TextStyle(
              color: AppTokens.textSecondary,
              fontSize: 14,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: BookingLocationDisplay(
            name: name,
            address: address,
            fallbackDisplayName: fallbackDisplayName,
            emphasizeName: emphasize,
          ),
        ),
      ],
    ),
  );
}

Widget bookingLocationOptionSummaryRow({
  required String label,
  required LocationOption? location,
  bool emphasize = false,
}) {
  if (location == null) {
    return bookingLocationSummaryRow(label: label, name: null, address: null);
  }
  return bookingLocationSummaryRow(
    label: label,
    name: location.name,
    address: location.address,
    fallbackDisplayName: location.displayName,
    emphasize: emphasize,
  );
}

String? _firstNonEmpty(List<String?> values) {
  for (final value in values) {
    final trimmed = value?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  }
  return null;
}

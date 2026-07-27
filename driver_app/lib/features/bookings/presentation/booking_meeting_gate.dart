import '../../dispatch/data/airport_label_resolver.dart';

String? resolveBkkAirportPickupMeetingGate({
  required String serviceTypeCode,
  required bool nameSignRequested,
  required Iterable<String?> pickupCandidates,
}) {
  if (serviceTypeCode.toUpperCase() != 'AIRPORT_PICKUP') return null;
  final isBkk = pickupCandidates
      .whereType<String>()
      .map(AirportLabelResolver.displayLabelFor)
      .any((label) => label.toUpperCase().startsWith('BKK'));
  if (!isBkk) return null;
  return nameSignRequested ? '3' : '7';
}

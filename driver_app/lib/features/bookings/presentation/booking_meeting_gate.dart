import '../../dispatch/data/airport_label_resolver.dart';

class MeetingGateInfo {
  const MeetingGateInfo({
    required this.gateNumber,
    this.nameSignText,
  });

  final String gateNumber;
  final String? nameSignText;
}

MeetingGateInfo? buildMeetingGateInfo({
  required String serviceTypeCode,
  required bool nameSignRequested,
  required Iterable<String?> pickupCandidates,
  String? nameSignText,
}) {
  if (serviceTypeCode.toUpperCase() != 'AIRPORT_PICKUP') return null;
  final isBkk = pickupCandidates
      .whereType<String>()
      .map(AirportLabelResolver.displayLabelFor)
      .any((label) => label.toUpperCase().startsWith('BKK'));
  if (!isBkk) return null;

  final gateNumber = nameSignRequested ? '3' : '7';
  String? resolvedNameSignText;
  if (nameSignRequested) {
    final trimmed = nameSignText?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      resolvedNameSignText = trimmed;
    }
  }

  return MeetingGateInfo(
    gateNumber: gateNumber,
    nameSignText: resolvedNameSignText,
  );
}

String? resolveBkkAirportPickupMeetingGate({
  required String serviceTypeCode,
  required bool nameSignRequested,
  required Iterable<String?> pickupCandidates,
}) {
  return buildMeetingGateInfo(
    serviceTypeCode: serviceTypeCode,
    nameSignRequested: nameSignRequested,
    pickupCandidates: pickupCandidates,
  )?.gateNumber;
}

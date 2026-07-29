import 'package:flutter_test/flutter_test.dart';
import 'package:tride_driver/features/bookings/presentation/booking_meeting_gate.dart';

void main() {
  const pickupCandidates = ['BKK — Suvarnabhumi Airport'];

  test('buildMeetingGateInfo returns gate 3 and nameSignText when requested', () {
    final info = buildMeetingGateInfo(
      serviceTypeCode: 'AIRPORT_PICKUP',
      nameSignRequested: true,
      pickupCandidates: pickupCandidates,
      nameSignText: '  KIM FAMILY  ',
    );

    expect(info, isNotNull);
    expect(info!.gateNumber, '3');
    expect(info.nameSignText, 'KIM FAMILY');
  });

  test('buildMeetingGateInfo returns gate 7 without nameSignText', () {
    final info = buildMeetingGateInfo(
      serviceTypeCode: 'AIRPORT_PICKUP',
      nameSignRequested: false,
      pickupCandidates: pickupCandidates,
      nameSignText: 'KIM FAMILY',
    );

    expect(info, isNotNull);
    expect(info!.gateNumber, '7');
    expect(info.nameSignText, isNull);
  });

  test('buildMeetingGateInfo returns null outside BKK airport pickup', () {
    expect(
      buildMeetingGateInfo(
        serviceTypeCode: 'CITY_TRANSFER',
        nameSignRequested: true,
        pickupCandidates: pickupCandidates,
        nameSignText: 'KIM FAMILY',
      ),
      isNull,
    );
  });
}

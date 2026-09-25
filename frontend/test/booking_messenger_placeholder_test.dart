import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/controllers/booking_wizard_controller.dart';
import 'package:frontend/features/booking/models/booking_wizard_state.dart';
import 'package:frontend/features/booking/services/booking_state_storage.dart';
import 'package:frontend/features/booking/utils/transitional_messenger_placeholders.dart';

import 'support/booking_wizard_test_helpers.dart';

void main() {
  test('sanitize clears transitional messenger draft values', () {
    expect(
      TransitionalMessengerPlaceholders.sanitizeMessengerTypeField('PENDING'),
      '',
    );
    expect(
      TransitionalMessengerPlaceholders.sanitizeMessengerTypeField(' PENDING '),
      '',
    );
    expect(
      TransitionalMessengerPlaceholders.sanitizeMessengerIdField('POST_CREATE'),
      '',
    );
    expect(
      TransitionalMessengerPlaceholders.sanitizeMessengerIdField('PENDING'),
      '',
    );
    expect(
      TransitionalMessengerPlaceholders.sanitizeMessengerTypeField('LINE'),
      'LINE',
    );
  });

  test('BookingWizardState.fromJson strips transitional messenger placeholders', () {
    final state = BookingWizardState.fromJson({
      'messengerType': 'PENDING',
      'messengerId': 'POST_CREATE',
    });
    expect(state.messengerType, '');
    expect(state.messengerId, '');
  });

  test('buildCreatePayload omits transitional placeholders and keeps real messenger', () async {
    final controller = await buildContractAirportPickupController();
    await controller.updateCustomerInfo(
      messengerType: 'PENDING',
      messengerId: 'POST_CREATE',
    );
    final withoutPlaceholders = controller.buildCreatePayload();
    final customerA = Map<String, dynamic>.from(withoutPlaceholders['customer'] as Map);
    expect(customerA.containsKey('messengerType'), isFalse);
    expect(customerA.containsKey('messengerId'), isFalse);

    await controller.updateCustomerInfo(
      messengerType: 'LINE',
      messengerId: 'line-user',
    );
    final withReal = controller.buildCreatePayload();
    final customerB = Map<String, dynamic>.from(withReal['customer'] as Map);
    expect(customerB['messengerType'], 'LINE');
    expect(customerB['messengerId'], 'line-user');
  });

  test('draft v3 restore clears transitional messenger fields from envelope', () async {
    final rawState = BookingWizardState.fromJson({
      'customerName': 'Kim',
      'customerPhone': '+66123456789',
      'messengerType': 'PENDING',
      'messengerId': 'POST_CREATE',
    });
    final persisted = BookingStateStorage.persistableState(rawState);
    expect(persisted.messengerType, '');
    expect(persisted.messengerId, '');
  });
}

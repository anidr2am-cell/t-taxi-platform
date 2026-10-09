'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createBookingSchema } = require('../src/validators/booking.validator');
const { normalizeMessengerType } = require('../src/utils/customerMessengerFields');

function payload(customer) {
  return {
    serviceTypeCode: 'AIRPORT_PICKUP',
    vehicleTypeCode: 'SEDAN',
    scheduledPickupAt: new Date(Date.now() + 86400000).toISOString(),
    origin: { address: 'BKK' },
    destination: { address: 'Pattaya' },
    passengers: { adults: 1 },
    customer: { name: 'Guest', ...customer },
  };
}

test('normalizes legacy messenger labels', () => {
  assert.equal(normalizeMessengerType('kakao talk'), 'KAKAO');
  assert.equal(normalizeMessengerType('line'), 'LINE');
  assert.equal(normalizeMessengerType('WhatsApp'), 'WHATSAPP');
  assert.equal(normalizeMessengerType('phone'), 'SMS');
});

test('allows Kakao and LINE without a phone', () => {
  for (const messengerType of ['KAKAO', 'LINE']) {
    const result = createBookingSchema.validate(payload({
      messengerType,
      messengerId: 'searchable-id',
    }));
    assert.equal(result.error, undefined);
    assert.equal(result.value.customer.phone, null);
  }
});

test('requires messenger type and id as a pair', () => {
  assert.ok(createBookingSchema.validate(payload({ messengerType: 'LINE' })).error);
  assert.ok(createBookingSchema.validate(payload({ messengerId: 'line-id' })).error);
});

test('keeps legacy phone-only booking requests compatible during rollout', () => {
  const result = createBookingSchema.validate(payload({ phone: '0812345678' }));
  assert.equal(result.error, undefined);
  assert.equal(result.value.customer.phone, '0812345678');
});

test('requires international WhatsApp and SMS numbers', () => {
  for (const messengerType of ['WHATSAPP', 'SMS']) {
    assert.ok(createBookingSchema.validate(payload({
      messengerType,
      messengerId: '0812345678',
      phone: '0812345678',
    })).error);
    const valid = createBookingSchema.validate(payload({
      messengerType,
      messengerId: '+66812345678',
      phone: '+66812345678',
    }));
    assert.equal(valid.error, undefined);
  }
});

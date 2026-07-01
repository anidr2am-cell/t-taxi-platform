const { test } = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { createBookingSchema } = require('../src/validators/booking.validator');
const BookingService = require('../src/services/booking.service');

function validPayload(overrides = {}) {
  return {
    serviceTypeCode: 'CITY_TRANSFER',
    vehicleTypeCode: 'SUV',
    vehicleCount: 1,
    scheduledPickupAt: '2099-07-01T09:30:00+07:00',
    origin: {
      address: 'Bangkok',
      placeId: 'origin',
      lat: 13.7563,
      lng: 100.5018,
      name: 'Bangkok',
    },
    destination: {
      address: 'Pattaya',
      placeId: 'destination',
      lat: 12.9236,
      lng: 100.8825,
      name: 'Pattaya',
    },
    passengers: {
      adults: 2,
      children: 0,
      infants: 0,
    },
    customer: {
      name: 'Kim',
      email: 'kim@example.com',
      phone: '+66123456789',
      countryCode: 'TH',
    },
    ...overrides,
  };
}

test('booking validator requires scheduledPickupAt', () => {
  const payload = validPayload();
  delete payload.scheduledPickupAt;

  const { error } = createBookingSchema.validate(payload);

  assert.ok(error);
  assert.match(error.message, /scheduledPickupAt/);
});

test('booking validator rejects pickup less than 2 hours from now', () => {
  const nearFuture = new Date(Date.now() + 60 * 60 * 1000).toISOString();

  const { error } = createBookingSchema.validate(validPayload({
    scheduledPickupAt: nearFuture,
  }));

  assert.ok(error);
  assert.match(error.message, /2 hours/);
});

test('booking validator accepts future scheduledPickupAt ISO-8601', () => {
  const { error, value } = createBookingSchema.validate(validPayload());

  assert.equal(error, undefined);
  assert.equal(value.scheduledPickupAt, '2099-07-01T02:30:00.000Z');
});

test('booking service stores scheduled pickup as Thailand service-local datetime', () => {
  const service = new BookingService(null, null, null, null, null, null, null);

  const stored = service.formatThailandDateTime('2026-07-01T09:30:00+07:00');

  assert.equal(stored, '2026-07-01 09:30:00');
});

const { test } = require('node:test');
const assert = require('node:assert/strict');

const {
  createBookingSchema,
  normalizeOptionalEmail,
} = require('../src/validators/booking.validator');

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

test('normalizeOptionalEmail trims whitespace-only to null', () => {
  assert.equal(normalizeOptionalEmail('   '), null);
  assert.equal(normalizeOptionalEmail(''), null);
  assert.equal(normalizeOptionalEmail(null), null);
  assert.equal(normalizeOptionalEmail(' user@example.com '), 'user@example.com');
});

test('booking validator accepts valid email', () => {
  const { error, value } = createBookingSchema.validate(validPayload());

  assert.equal(error, undefined);
  assert.equal(value.customer.email, 'kim@example.com');
});

test('booking validator accepts missing customer email', () => {
  const payload = validPayload({
    customer: {
      name: 'Kim',
      phone: '+66123456789',
      countryCode: 'TH',
    },
  });

  const { error, value } = createBookingSchema.validate(payload);

  assert.equal(error, undefined);
  assert.equal(value.customer.email, null);
});

test('booking validator accepts null customer email', () => {
  const { error, value } = createBookingSchema.validate(validPayload({
    customer: {
      name: 'Kim',
      email: null,
      phone: '+66123456789',
      countryCode: 'TH',
    },
  }));

  assert.equal(error, undefined);
  assert.equal(value.customer.email, null);
});

test('booking validator normalizes empty customer email to null', () => {
  const { error, value } = createBookingSchema.validate(validPayload({
    customer: {
      name: 'Kim',
      email: '   ',
      phone: '+66123456789',
      countryCode: 'TH',
    },
  }));

  assert.equal(error, undefined);
  assert.equal(value.customer.email, null);
});

test('booking validator rejects invalid customer email', () => {
  const { error } = createBookingSchema.validate(validPayload({
    customer: {
      name: 'Kim',
      email: 'not-an-email',
      phone: '+66123456789',
      countryCode: 'TH',
    },
  }));

  assert.ok(error);
  assert.match(error.message, /email/i);
});

test('booking validator still requires customer name and phone', () => {
  const missingName = createBookingSchema.validate(validPayload({
    customer: {
      phone: '+66123456789',
      countryCode: 'TH',
    },
  }));
  assert.ok(missingName.error);
  assert.match(missingName.error.message, /name/i);

  const missingPhone = createBookingSchema.validate(validPayload({
    customer: {
      name: 'Kim',
      countryCode: 'TH',
    },
  }));
  assert.ok(missingPhone.error);
  assert.match(missingPhone.error.message, /phone/i);
});

test('booking validator accepts valid countryCode', () => {
  const { error, value } = createBookingSchema.validate(validPayload({
    customer: {
      name: 'Kim',
      phone: '+66123456789',
      countryCode: ' th ',
    },
  }));

  assert.equal(error, undefined);
  assert.equal(value.customer.countryCode, 'TH');
});

test('booking validator rejects missing countryCode', () => {
  const { error } = createBookingSchema.validate(validPayload({
    customer: {
      name: 'Kim',
      phone: '+66123456789',
    },
  }));

  assert.ok(error);
  assert.match(error.message, /countryCode/i);
});

test('booking validator rejects null countryCode', () => {
  const { error } = createBookingSchema.validate(validPayload({
    customer: {
      name: 'Kim',
      phone: '+66123456789',
      countryCode: null,
    },
  }));

  assert.ok(error);
  assert.match(error.message, /countryCode/i);
});

test('booking validator rejects empty countryCode', () => {
  const { error } = createBookingSchema.validate(validPayload({
    customer: {
      name: 'Kim',
      phone: '+66123456789',
      countryCode: '',
    },
  }));

  assert.ok(error);
  assert.match(error.message, /countryCode/i);
});

test('booking validator rejects whitespace-only countryCode', () => {
  const { error } = createBookingSchema.validate(validPayload({
    customer: {
      name: 'Kim',
      phone: '+66123456789',
      countryCode: '   ',
    },
  }));

  assert.ok(error);
  assert.match(error.message, /countryCode/i);
});

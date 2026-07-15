const { test } = require('node:test');
const assert = require('node:assert/strict');

const {
  createBookingSchema,
  normalizeOptionalEmail,
} = require('../src/validators/booking.validator');
const validate = require('../src/middlewares/validate.middleware');
const ERROR_CODES = require('../src/constants/errorCodes');

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

test('booking validator accepts multilingual customer names and free-text places', () => {
  const names = [
    'สมชาย ใจดี',
    '박용세',
    "John O'Connor",
    'Nguyễn Văn An',
    'محمد علي',
    '王小明',
    'Kim 123',
  ];

  for (const name of names) {
    const { error, value } = createBookingSchema.validate(validPayload({
      origin: {
        address: 'กรุงเทพฯ / พัทยา',
        placeId: 'origin',
        lat: 13.7563,
        lng: 100.5018,
        name: 'Hotel & Residence',
      },
      customer: {
        name: `  ${name}  `,
        phone: '+66123456789',
        countryCode: 'TH',
      },
      additionalRequests: 'Soi 6/1 — พบที่ล็อบบี้',
    }));

    assert.equal(error, undefined, name);
    assert.equal(value.customer.name, name.normalize('NFC'));
    assert.equal(value.origin.address, 'กรุงเทพฯ / พัทยา');
    assert.equal(value.additionalRequests, 'Soi 6/1 — พบที่ล็อบบี้');
  }
});

test('booking validator rejects blank, control-character, and too-long customer names', () => {
  const blank = createBookingSchema.validate(validPayload({
    customer: { name: '   ', phone: '+66123456789' },
  }));
  assert.ok(blank.error);
  assert.equal(blank.error.details[0].path.join('.'), 'customer.name');

  const control = createBookingSchema.validate(validPayload({
    customer: { name: 'Kim\u0000', phone: '+66123456789' },
  }));
  assert.ok(control.error);
  assert.equal(control.error.details[0].type, 'string.controlCharacters');

  const tooLong = createBookingSchema.validate(validPayload({
    customer: { name: '가'.repeat(101), phone: '+66123456789' },
  }));
  assert.ok(tooLong.error);
  assert.equal(tooLong.error.details[0].type, 'string.max');
});

test('booking validator accepts optional countryCode and free text', () => {
  const cases = [
    { countryCode: ' th ', expected: 'th' },
    { countryCode: 'Korea', expected: 'Korea' },
    { countryCode: '대한민국', expected: '대한민국' },
    { countryCode: '', expected: null },
    { countryCode: '   ', expected: null },
    { countryCode: null, expected: null },
  ];

  for (const { countryCode, expected } of cases) {
    const { error, value } = createBookingSchema.validate(validPayload({
      customer: {
        name: 'Kim',
        phone: '+66123456789',
        countryCode,
      },
    }));

    assert.equal(error, undefined, `countryCode=${JSON.stringify(countryCode)}`);
    assert.equal(value.customer.countryCode, expected);
  }
});

test('booking validator accepts missing countryCode', () => {
  const { error, value } = createBookingSchema.validate(validPayload({
    customer: {
      name: 'Kim',
      phone: '+66123456789',
    },
  }));

  assert.equal(error, undefined);
  assert.equal(value.customer.countryCode, null);
});

test('booking validator accepts and normalizes alphanumeric flight numbers', () => {
  const cases = [
    ['TG401', 'TG401'],
    [' TG 401 ', 'TG401'],
    ['TG-401', 'TG401'],
    ['KE651', 'KE651'],
    ['OZ741', 'OZ741'],
    ['7C2203', '7C2203'],
    ['7c 2203', '7C2203'],
    ['7c-2203', '7C2203'],
    ['5J931', '5J931'],
    ['6E1053', '6E1053'],
    ['3K513', '3K513'],
    ['U28001', 'U28001'],
    ['EK372', 'EK372'],
    ['THA401', 'THA401'],
    ['TG401A', 'TG401A'],
  ];

  for (const [input, expected] of cases) {
    const { error, value } = createBookingSchema.validate(validPayload({
      serviceTypeCode: 'AIRPORT_PICKUP',
      transfer: { airportIata: 'BKK', flightNumber: input },
    }));

    assert.equal(error, undefined, input);
    assert.equal(value.transfer.flightNumber, expected);
  }
});

test('booking validator treats blank flight numbers as null', () => {
  for (const flightNumber of [null, '', '   ']) {
    const { error, value } = createBookingSchema.validate(validPayload({
      serviceTypeCode: 'AIRPORT_PICKUP',
      transfer: { airportIata: 'BKK', flightNumber },
    }));

    assert.equal(error, undefined, JSON.stringify(flightNumber));
    assert.equal(value.transfer.flightNumber, null);
  }
});

test('booking validator rejects unsafe or malformed flight numbers', () => {
  for (const flightNumber of [
    '1234',
    '122203',
    'T401',
    'TTTT401',
    'TG',
    'TGABC',
    'TG@401',
    'TG/401',
    '✈️TG401',
    'TG\u0000401',
    'TG123456789012345678901',
  ]) {
    const { error } = createBookingSchema.validate(validPayload({
      serviceTypeCode: 'AIRPORT_PICKUP',
      transfer: { airportIata: 'BKK', flightNumber },
    }));

    assert.ok(error, flightNumber);
    assert.equal(error.details[0].path.join('.'), 'transfer.flightNumber');
    assert.equal(error.details[0].type, flightNumber.length > 20 ? 'string.max' : 'any.invalid');
  }
});

test('booking validation middleware reports flight number field details', () => {
  const req = {
    body: validPayload({
      serviceTypeCode: 'AIRPORT_PICKUP',
      transfer: { airportIata: 'BKK', flightNumber: 'TG/401' },
    }),
  };
  let capturedError;

  validate({ body: createBookingSchema })(req, {}, (err) => {
    capturedError = err;
  });

  assert.equal(capturedError.errorCode, ERROR_CODES.VALIDATION_ERROR);
  assert.equal(capturedError.errors[0].field, 'transfer.flightNumber');
  assert.equal(capturedError.errors[0].type, 'any.invalid');
  assert.equal(capturedError.errors[0].source, 'body');
  assert.match(capturedError.errors[0].message, /TG401, 7C2203/);
});

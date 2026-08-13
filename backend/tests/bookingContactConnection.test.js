const test = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = 'test';
process.env.DB_USER = 'test';
process.env.DB_NAME = 'tride_test';
process.env.JWT_ACCESS_SECRET = 'test-access-secret';
process.env.JWT_REFRESH_SECRET = 'test-refresh-secret';
process.env.CONTACT_CONNECTION_REQUIRED = 'false';

const {
  isContactConnectionRequired,
  isBookingContactVerified,
  assertBookingDispatchEligible,
} = require('../src/policies/bookingDispatchEligibility.policy');
const CONTACT_STATUS = require('../src/constants/contactStatus');
const BookingService = require('../src/services/booking.service');
const BOOKING_STATUS = require('../src/constants/reservationStatus');

test('dispatch policy passes when feature flag is disabled', () => {
  assert.equal(isContactConnectionRequired(), false);
  assert.equal(isBookingContactVerified({ contact_status: 'PENDING' }), true);
  assert.doesNotThrow(() => assertBookingDispatchEligible({ contact_status: 'PENDING' }));
});

test('dispatch policy blocks unverified when feature flag enabled', () => {
  const previous = process.env.CONTACT_CONNECTION_REQUIRED;
  process.env.CONTACT_CONNECTION_REQUIRED = 'true';
  delete require.cache[require.resolve('../src/config/env')];
  delete require.cache[require.resolve('../src/policies/bookingDispatchEligibility.policy')];
  const policy = require('../src/policies/bookingDispatchEligibility.policy');

  assert.equal(policy.isContactConnectionRequired(), true);
  assert.equal(
    policy.isBookingContactVerified({ contact_status: CONTACT_STATUS.CONFIRM_REQUESTED }),
    false,
  );
  assert.throws(
    () => policy.assertBookingDispatchEligible({ contact_status: CONTACT_STATUS.PENDING }),
    (err) => err.errorCode === 'BOOKING_CONTACT_NOT_VERIFIED',
  );

  process.env.CONTACT_CONNECTION_REQUIRED = previous;
  delete require.cache[require.resolve('../src/config/env')];
  delete require.cache[require.resolve('../src/policies/bookingDispatchEligibility.policy')];
});

test('create uses pending contact status when feature flag enabled', () => {
  const previous = process.env.CONTACT_CONNECTION_REQUIRED;
  process.env.CONTACT_CONNECTION_REQUIRED = 'true';
  delete require.cache[require.resolve('../src/config/env')];
  delete require.cache[require.resolve('../src/policies/bookingDispatchEligibility.policy')];
  delete require.cache[require.resolve('../src/services/booking.service')];
  const BookingServiceFresh = require('../src/services/booking.service');
  const CONTACT_STATUS = require('../src/constants/contactStatus');
  const service = new BookingServiceFresh({}, {}, {}, {}, {}, {}, null, null, null, null, null, null, null, null, null, null);
  assert.equal(service.resolveInitialContactStatus(), CONTACT_STATUS.PENDING);
  process.env.CONTACT_CONNECTION_REQUIRED = previous;
  delete require.cache[require.resolve('../src/config/env')];
  delete require.cache[require.resolve('../src/policies/bookingDispatchEligibility.policy')];
  delete require.cache[require.resolve('../src/services/booking.service')];
});

test('create uses verified contact status when feature flag disabled', () => {
  const previous = process.env.CONTACT_CONNECTION_REQUIRED;
  process.env.CONTACT_CONNECTION_REQUIRED = 'false';
  delete require.cache[require.resolve('../src/config/env')];
  delete require.cache[require.resolve('../src/policies/bookingDispatchEligibility.policy')];
  delete require.cache[require.resolve('../src/services/booking.service')];
  const BookingServiceFresh = require('../src/services/booking.service');
  const CONTACT_STATUS = require('../src/constants/contactStatus');
  const service = new BookingServiceFresh({}, {}, {}, {}, {}, {}, null, null, null, null, null, null, null, null, null, null);
  assert.equal(service.resolveInitialContactStatus(), CONTACT_STATUS.VERIFIED);
  assert.equal(service.shouldDeferDispatchUntilContactVerified(), false);
  process.env.CONTACT_CONNECTION_REQUIRED = previous;
  delete require.cache[require.resolve('../src/config/env')];
  delete require.cache[require.resolve('../src/policies/bookingDispatchEligibility.policy')];
  delete require.cache[require.resolve('../src/services/booking.service')];
});

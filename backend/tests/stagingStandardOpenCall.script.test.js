const test = require('node:test');
const assert = require('node:assert/strict');

const { createBookingIdempotencyKey } = require('../scripts/staging-booking-regression');
const {
  E2E_MARKER,
  bookingPayload,
  assertValidPayload,
  assertNotInOpenCalls,
  assertOpenCallItemShape,
  assertPostCreateAdminDetail,
  assertSafeArchiveDetail,
  pickEnabledContactChannel,
} = require('../scripts/staging-standard-open-call');

test('createBookingIdempotencyKey returns unique UUID values', () => {
  const first = createBookingIdempotencyKey();
  const second = createBookingIdempotencyKey();
  assert.match(first, /^[0-9a-f-]{36}$/i);
  assert.notEqual(first, second);
});

test('bookingPayload validates against createBookingSchema', () => {
  assertValidPayload(bookingPayload());
  assert.equal(bookingPayload().additionalRequests, E2E_MARKER);
});

test('assertNotInOpenCalls rejects leaked booking', () => {
  assert.throws(
    () => assertNotInOpenCalls(
      { data: { items: [{ bookingNumber: 'TX202608130001' }] } },
      'TX202608130001',
      'leaked',
    ),
    /leaked/,
  );
});

test('pickEnabledContactChannel prefers LINE when enabled', () => {
  const channel = pickEnabledContactChannel({
    channels: [
      { code: 'WHATSAPP', enabled: true },
      { code: 'LINE', enabled: true },
    ],
  });
  assert.equal(channel, 'LINE');
});

test('assertPostCreateAdminDetail enforces PENDING contact gate state', () => {
  assert.doesNotThrow(() => assertPostCreateAdminDetail({
    bookingNumber: 'TX202608130001',
    status: 'OPEN',
    customer: { name: '[E2E] STANDARD Open Call', contactStatus: 'PENDING' },
    activeAssignment: null,
    specialRequests: E2E_MARKER,
  }, 'TX202608130001'));
});

test('assertOpenCallItemShape validates visible open-call item', () => {
  const payload = bookingPayload();
  assert.doesNotThrow(() => assertOpenCallItemShape({
    bookingNumber: 'TX202608130001',
    serviceType: { code: payload.serviceTypeCode },
    origin: 'BKK',
    destination: 'Pattaya',
    scheduledPickupAt: payload.scheduledPickupAt,
    vehicleType: { code: 'SUV' },
    amount: 1000,
    currency: 'THB',
    isUrgentRequest: false,
    compatibleVehicles: [{ id: 1 }],
  }, 'TX202608130001', payload));
});

test('assertSafeArchiveDetail refuses bookings without E2E marker', () => {
  assert.throws(
    () => assertSafeArchiveDetail(
      {
        bookingNumber: 'TX202608130001',
        customer: { name: '[E2E] STANDARD Open Call' },
        specialRequests: 'OTHER',
      },
      { bookingNumber: 'TX202608130001' },
    ),
    /E2E marker/,
  );
});

const test = require('node:test');
const assert = require('node:assert/strict');

const DriverSuspensionService = require('../src/services/driverSuspension.service');
const { assertDriverOperational } = require('../src/policies/driverOperational.policy');
const ERROR_CODES = require('../src/constants/errorCodes');

function service() {
  return new DriverSuspensionService({
    pool: {},
    driverRepository: {},
    userRepository: {},
    bookingRepository: {},
    bookingAssignmentReopenService: {},
    driverCallService: {},
  });
}

test('operational policy blocks suspended drivers with stable 403 code', () => {
  assert.throws(
    () => assertDriverOperational({ id: 2, status: 'SUSPENDED', is_active: 1, user_is_active: 1 }),
    (error) => error.statusCode === 403 && error.errorCode === ERROR_CODES.DRIVER_SUSPENDED,
  );
});

test('operational policy allows available and offline drivers', () => {
  assert.doesNotThrow(() => assertDriverOperational({ status: 'AVAILABLE', is_active: 1, user_is_active: 1 }));
  assert.doesNotThrow(() => assertDriverOperational({ status: 'OFFLINE', is_active: 1, user_is_active: 1 }));
});

test('suspension preview releases only future unstarted assignments', () => {
  const now = Date.parse('2026-10-11T00:00:00.000Z');
  const result = service().classify([
    { booking_number: 'QA_FUTURE', status: 'DRIVER_ASSIGNED', scheduled_pickup_at: '2026-10-11 12:00:00' },
    { booking_number: 'QA_RUNNING', status: 'ON_ROUTE', scheduled_pickup_at: '2026-10-11 13:00:00' },
    { booking_number: 'QA_OVERDUE', status: 'DRIVER_ASSIGNED', scheduled_pickup_at: '2026-10-10 06:00:00' },
  ], now);
  assert.deepEqual(result.releasable.map((item) => item.bookingNumber), ['QA_FUTURE']);
  assert.deepEqual(result.blocking.map((item) => item.bookingNumber), ['QA_RUNNING', 'QA_OVERDUE']);
  assert.equal(result.releasable[0].within24Hours, true);
  assert.equal(result.blocking[0].reason, 'TRIP_IN_PROGRESS');
  assert.equal(result.blocking[1].reason, 'PICKUP_TIME_PASSED_OR_MISSING');
});

test('audit payload parser accepts object, JSON string, buffer, and malformed data', () => {
  const target = service();
  assert.equal(target.parseAuditPayload({ reason: 'a' }).reason, 'a');
  assert.equal(target.parseAuditPayload('{"reason":"b"}').reason, 'b');
  assert.equal(target.parseAuditPayload(Buffer.from('{"reason":"c"}')).reason, 'c');
  assert.deepEqual(target.parseAuditPayload('invalid'), {});
});


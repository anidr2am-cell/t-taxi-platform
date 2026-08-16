const test = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = 'test';
process.env.DB_USER = 'test';
process.env.DB_NAME = 'tride_test';
process.env.JWT_ACCESS_SECRET = 'test-access-secret';
process.env.JWT_REFRESH_SECRET = 'test-refresh-secret';
process.env.CONTACT_CONNECTION_REQUIRED = 'true';

delete require.cache[require.resolve('../src/config/env')];
delete require.cache[require.resolve('../src/policies/bookingDispatchEligibility.policy')];

const CONTACT_STATUS = require('../src/constants/contactStatus');
const BOOKING_STATUS = require('../src/constants/reservationStatus');
const BookingService = require('../src/services/booking.service');
const { createLockState, createSerializedLockState } = require('./support/mysqlAdvisoryLock.helpers');

function createDispatchHarness(overrides = {}) {
  const metadataUpdates = [];
  const bookingRow = {
    id: 5,
    contact_status: CONTACT_STATUS.VERIFIED,
    status: BOOKING_STATUS.OPEN,
    metadata: JSON.stringify(overrides.metadata ?? {}),
    ...overrides.bookingRow,
  };
  const lockState = overrides.lockState ?? createLockState();
  const pool = {
    async getConnection() {
      return lockState.createConn();
    },
  };
  const bookingRepository = {
    async findById(id) {
      return { ...bookingRow, id };
    },
    async findOpenDriverCallByBookingId(_conn, id) {
      return {
        id,
        booking_number: 'TX202608130020',
        contact_status: CONTACT_STATUS.VERIFIED,
        status: BOOKING_STATUS.OPEN,
        metadata: bookingRow.metadata,
        vehicle_type_id: 1,
        scheduled_pickup_at: '2026-08-13 09:00:00',
        total_amount: 1000,
        currency: 'THB',
        payment_method: 'PAY_DRIVER',
        is_urgent_request: 0,
        service_type_code: 'AIRPORT_PICKUP',
        service_type_name: 'Airport Pickup',
        vehicle_type_code: 'SEDAN',
        vehicle_type_name: 'Sedan',
        origin_address: 'BKK',
        destination_address: 'Hotel',
        ...overrides.openCallRow,
      };
    },
    async updateCommissionFields(_conn, bookingId, fields) {
      metadataUpdates.push({ bookingId, metadata: fields.metadata });
      bookingRow.metadata = JSON.stringify(fields.metadata);
    },
  };

  const service = new BookingService(
    pool,
    bookingRepository,
    {},
    {},
    {},
    {},
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
  );

  let notificationCount = 0;
  service.getEligibleDriversForOpenBooking = async () => [{ id: 1, user_id: 2 }];
  service.mapEligibleDriversToTargets = (drivers) => drivers.map((d) => ({
    driverId: d.id,
    userId: d.user_id,
  }));
  service.buildOpenCallPayload = () => ({ bookingNumber: 'TX202608130020' });
  service.parseBookingMetadata = BookingService.prototype.parseBookingMetadata;
  service.isContactDispatchCompleted = BookingService.prototype.isContactDispatchCompleted;
  service.markContactDispatchCompleted = BookingService.prototype.markContactDispatchCompleted;
  service.markContactDispatchDelivered = BookingService.prototype.markContactDispatchDelivered;
  service.persistOpenCallNotificationsTx = async () => {
    if (overrides.dispatchDelayMs) {
      await new Promise((resolve) => setTimeout(resolve, overrides.dispatchDelayMs));
    }
    if (overrides.dispatchThrows) {
      throw overrides.dispatchThrows;
    }
    notificationCount += 1;
    return [{ notificationId: 1, created: true, driver: { id: 1, user_id: 2 } }];
  };
  service.persistUrgentCallNotificationsTx = async () => [];
  service.dispatchContactDispatchPostCommit = async () => {};

  return {
    service,
    bookingRow,
    metadataUpdates,
    lockState,
    getNotificationCount: () => notificationCount,
  };
}

test('concurrent dispatchAfterContactVerified runs side effects once', async () => {
  const harness = createDispatchHarness({
    lockState: createSerializedLockState(),
    dispatchDelayMs: 40,
  });

  const [first, second] = await Promise.all([
    harness.service.dispatchAfterContactVerified(harness.bookingRow),
    harness.service.dispatchAfterContactVerified(harness.bookingRow),
  ]);

  const results = [first, second].sort();
  assert.deepEqual(results, [false, true]);
  assert.equal(harness.getNotificationCount(), 1);
  assert.equal(harness.metadataUpdates.length, 2);
  assert.equal(harness.metadataUpdates[0].metadata.contactDispatchCompleted, true);
  assert.equal(harness.metadataUpdates[1].metadata.contactDispatchDelivered, true);
});

test('dispatchAfterContactVerified keeps marker absent when side effects fail', async () => {
  const harness = createDispatchHarness({
    dispatchThrows: new Error('notification failed'),
  });

  await assert.rejects(
    () => harness.service.dispatchAfterContactVerified(harness.bookingRow),
    /notification failed/,
  );

  assert.equal(harness.metadataUpdates.length, 0);
  assert.equal(harness.getNotificationCount(), 0);

  const retry = createDispatchHarness();
  retry.bookingRow.id = harness.bookingRow.id;
  const dispatched = await retry.service.dispatchAfterContactVerified(retry.bookingRow);
  assert.equal(dispatched, true);
  assert.equal(retry.getNotificationCount(), 1);
});

test('dispatchAfterContactVerified skips side effects when durable and delivery markers are complete', async () => {
  const harness = createDispatchHarness({
    metadata: { contactDispatchCompleted: true, contactDispatchDelivered: true },
  });

  const dispatched = await harness.service.dispatchAfterContactVerified(harness.bookingRow);
  assert.equal(dispatched, false);
  assert.equal(harness.getNotificationCount(), 0);
  assert.equal(harness.metadataUpdates.length, 0);
});

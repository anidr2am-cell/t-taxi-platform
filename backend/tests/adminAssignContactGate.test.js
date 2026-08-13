const test = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = 'test';
process.env.DB_USER = 'test';
process.env.DB_NAME = 'tride_test';
process.env.JWT_ACCESS_SECRET = 'test-access-secret';
process.env.JWT_REFRESH_SECRET = 'test-refresh-secret';

const CONTACT_STATUS = require('../src/constants/contactStatus');
const BOOKING_STATUS = require('../src/constants/reservationStatus');
const ERROR_CODES = require('../src/constants/errorCodes');

function createConn() {
  return {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };
}

function buildHarness(contactStatus) {
  const pool = {
    async getConnection() {
      return createConn();
    },
  };

  const booking = {
    id: 10,
    booking_number: 'TX202608130010',
    status: BOOKING_STATUS.OPEN,
    contact_status: contactStatus,
    vehicle_type_id: 2,
    scheduled_pickup_at: '2026-08-13 09:00:00',
  };

  const bookingRepository = {
    async findByBookingNumberForUpdate() {
      return booking;
    },
    async findActiveAssignmentForUpdate() {
      return null;
    },
    async insertDriverAssignment() {
      return 99;
    },
    async insertActivityLog() {},
  };

  const driverRepository = {
    async findByIdForUpdate() {
      return {
        id: 7,
        name: 'Driver',
        user_id: 3,
        status: 'AVAILABLE',
        is_active: 1,
        is_online: 1,
        user_is_active: 1,
      };
    },
    async hasActiveJob() {
      return false;
    },
    async findPrimaryVehicle() {
      return { id: 100 };
    },
  };

  const bookingStatusService = {
    async transitionInTransaction() {
      return { outboxId: null };
    },
  };

  delete require.cache[require.resolve('../src/services/adminDispatch.service')];
  const AdminDispatchService = require('../src/services/adminDispatch.service');
  const service = new AdminDispatchService(
    pool,
    bookingRepository,
    driverRepository,
    bookingStatusService,
    {
      async driverHasBlockingSettlement() {
        return false;
      },
    },
  );

  return service;
}

function withFlag(enabled, fn) {
  const previous = process.env.CONTACT_CONNECTION_REQUIRED;
  process.env.CONTACT_CONNECTION_REQUIRED = enabled ? 'true' : 'false';
  delete require.cache[require.resolve('../src/config/env')];
  delete require.cache[require.resolve('../src/policies/bookingDispatchEligibility.policy')];
  return fn().finally(() => {
    process.env.CONTACT_CONNECTION_REQUIRED = previous;
    delete require.cache[require.resolve('../src/config/env')];
    delete require.cache[require.resolve('../src/policies/bookingDispatchEligibility.policy')];
  });
}

test('manual assign rejects PENDING when contact flag enabled', async () => {
  await withFlag(true, async () => {
    const service = buildHarness(CONTACT_STATUS.PENDING);
    await assert.rejects(
      () => service.assignDriver('TX202608130010', { driverId: 7 }, { id: 1, role: 'ADMIN' }),
      (err) => err.errorCode === ERROR_CODES.BOOKING_CONTACT_NOT_VERIFIED,
    );
  });
});

test('manual assign rejects CONFIRM_REQUESTED when contact flag enabled', async () => {
  await withFlag(true, async () => {
    const service = buildHarness(CONTACT_STATUS.CONFIRM_REQUESTED);
    await assert.rejects(
      () => service.assignDriver('TX202608130010', { driverId: 7 }, { id: 1, role: 'ADMIN' }),
      (err) => err.errorCode === ERROR_CODES.BOOKING_CONTACT_NOT_VERIFIED,
    );
  });
});

test('manual assign allows VERIFIED when contact flag enabled', async () => {
  await withFlag(true, async () => {
    const service = buildHarness(CONTACT_STATUS.VERIFIED);
    const result = await service.assignDriver(
      'TX202608130010',
      { driverId: 7 },
      { id: 1, role: 'ADMIN' },
    );
    assert.equal(result.assignmentId, 99);
  });
});

test('manual assign allows PENDING when contact flag disabled', async () => {
  await withFlag(false, async () => {
    const service = buildHarness(CONTACT_STATUS.PENDING);
    const result = await service.assignDriver(
      'TX202608130010',
      { driverId: 7 },
      { id: 1, role: 'ADMIN' },
    );
    assert.equal(result.assignmentId, 99);
  });
});

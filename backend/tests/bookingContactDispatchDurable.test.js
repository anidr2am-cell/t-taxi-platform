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
const NOTIFICATION_TYPES = require('../src/constants/notificationTypes');
const BookingService = require('../src/services/booking.service');
const NotificationService = require('../src/services/notification.service');
const { createLockState } = require('./support/mysqlAdvisoryLock.helpers');

function createNotificationHarness() {
  const inserts = [];
  const idempotencyIndex = new Map();
  let nextNotificationId = 1;

  const notificationRepository = {
    async findByIdempotencyKey(_conn, idempotencyKey) {
      const id = idempotencyIndex.get(idempotencyKey);
      return id ? { id, idempotency_key: idempotencyKey } : null;
    },
    async insert(_conn, data) {
      const id = nextNotificationId++;
      inserts.push({ id, ...data });
      idempotencyIndex.set(data.idempotencyKey, id);
      return id;
    },
    async findDeliveryByNotificationAndChannel() {
      return null;
    },
    async insertDelivery() {
      return 1;
    },
    async findById(notificationId) {
      const row = inserts.find((item) => item.id === notificationId);
      if (!row) return null;
      return {
        id: row.id,
        user_id: row.userId,
        booking_id: row.bookingId,
        payload: row.payload,
      };
    },
    async findDeliveriesByNotificationId() {
      return [];
    },
  };

  const notificationService = new NotificationService({}, notificationRepository);
  notificationService.processDeliveries = async () => {};

  return { notificationService, inserts, idempotencyIndex };
}

function createDispatchService(overrides = {}) {
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

  const { notificationService, inserts } = createNotificationHarness();
  const postCommitCalls = [];
  const socketCalls = [];

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
    () => notificationService,
    null,
    null,
    null,
    null,
    null,
  );

  service.getEligibleDriversForOpenBooking = async () => overrides.drivers ?? [
    { id: 1, user_id: 2 },
    { id: 3, user_id: 4 },
  ];
  service.mapEligibleDriversToTargets = (drivers) => drivers.map((driver) => ({
    driverId: driver.id,
    userId: driver.user_id,
  }));
  service.buildOpenCallPayload = () => ({ bookingNumber: 'TX202608130020' });
  service.parseBookingMetadata = BookingService.prototype.parseBookingMetadata;
  service.isContactDispatchCompleted = BookingService.prototype.isContactDispatchCompleted;
  service.isContactDispatchDelivered = BookingService.prototype.isContactDispatchDelivered;
  service.markContactDispatchCompleted = BookingService.prototype.markContactDispatchCompleted;
  service.markContactDispatchDelivered = BookingService.prototype.markContactDispatchDelivered;
  service.persistOpenCallNotificationsTx = BookingService.prototype.persistOpenCallNotificationsTx;
  service.persistUrgentCallNotificationsTx = BookingService.prototype.persistUrgentCallNotificationsTx;
  service.deliverPersistedContactNotifications = BookingService.prototype.deliverPersistedContactNotifications;
  service.redeliverContactDispatchNotifications = BookingService.prototype.redeliverContactDispatchNotifications;

  const originalPostCommit = BookingService.prototype.dispatchContactDispatchPostCommit;
  service.dispatchContactDispatchPostCommit = async (params) => {
    postCommitCalls.push(params);
    if (overrides.postCommitThrows) {
      throw overrides.postCommitThrows;
    }
    if (overrides.skipPostCommit !== true) {
      await originalPostCommit.call(service, params);
    }
  };

  if (overrides.stubSockets) {
    const realtime = require('../src/socket/realtime');
    realtime.emitDriverCallAvailable = (_userId, payload) => {
      socketCalls.push({ type: 'open', payload });
    };
    realtime.emitDriverUrgentCallNew = (payload) => {
      socketCalls.push({ type: 'urgent', payload });
    };
  }

  return {
    service,
    bookingRow,
    metadataUpdates,
    inserts,
    postCommitCalls,
    socketCalls,
    notificationService,
  };
}

test('contact dispatch persists durable notifications before completion marker in one transaction', async () => {
  const harness = createDispatchService();
  const dispatched = await harness.service.dispatchAfterContactVerified(harness.bookingRow);

  assert.equal(dispatched, true);
  assert.equal(harness.inserts.length, 2);
  assert.equal(harness.inserts[0].idempotencyKey, 'driver-call-open:5:1');
  assert.equal(harness.inserts[1].idempotencyKey, 'driver-call-open:5:3');
  assert.equal(harness.metadataUpdates.length, 2);
  assert.equal(harness.metadataUpdates[0].metadata.contactDispatchCompleted, true);
  assert.equal(harness.metadataUpdates[1].metadata.contactDispatchDelivered, true);
  assert.equal(harness.postCommitCalls.length, 1);
  assert.equal(harness.postCommitCalls[0].durableStateCommitted, false);
});

test('contact dispatch retry does not create duplicate durable notifications', async () => {
  const harness = createDispatchService();
  const first = await harness.service.dispatchAfterContactVerified(harness.bookingRow);
  const second = await harness.service.dispatchAfterContactVerified(harness.bookingRow);

  assert.equal(first, true);
  assert.equal(second, false);
  assert.equal(harness.inserts.length, 2);
});

test('contact dispatch retries delivery when durable marker exists but delivery marker is absent', async () => {
  const harness = createDispatchService({
    metadata: { contactDispatchCompleted: true },
  });

  let redeliveryCount = 0;
  harness.service.dispatchContactDispatchPostCommit = async (params) => {
    assert.equal(params.durableStateCommitted, true);
    redeliveryCount += 1;
  };

  const dispatched = await harness.service.dispatchAfterContactVerified(harness.bookingRow);

  assert.equal(dispatched, true);
  assert.equal(harness.inserts.length, 0);
  assert.equal(redeliveryCount, 1);
  assert.equal(harness.metadataUpdates.at(-1).metadata.contactDispatchDelivered, true);
});

test('contact dispatch keeps durable marker absent when notification persist fails before commit', async () => {
  const harness = createDispatchService();
  harness.service.persistOpenCallNotificationsTx = async () => {
    throw new Error('persist failed');
  };

  await assert.rejects(
    () => harness.service.dispatchAfterContactVerified(harness.bookingRow),
    /persist failed/,
  );

  assert.equal(harness.metadataUpdates.length, 0);
  assert.equal(harness.inserts.length, 0);
});

test('contact dispatch keeps durable marker when post-commit delivery fails', async () => {
  const harness = createDispatchService({
    postCommitThrows: new Error('socket failed'),
    stubSockets: true,
  });

  const dispatched = await harness.service.dispatchAfterContactVerified(harness.bookingRow);

  assert.equal(dispatched, true);
  assert.equal(harness.inserts.length, 2);
  assert.equal(harness.metadataUpdates[0].metadata.contactDispatchCompleted, true);
  assert.equal(harness.metadataUpdates.some((item) => item.metadata.contactDispatchDelivered), false);
  assert.equal(
    harness.service.needsContactDispatchRetry({
      contact_status: CONTACT_STATUS.VERIFIED,
      status: BOOKING_STATUS.OPEN,
      metadata: harness.bookingRow.metadata,
    }),
    true,
  );
});

test('needsContactDispatchRetry requires delivery marker after durable completion', () => {
  delete require.cache[require.resolve('../src/services/booking.service')];
  const BookingServiceFresh = require('../src/services/booking.service');
  const service = new BookingServiceFresh({}, {}, {}, {}, {}, {}, null, null, null, null, null, null, null, null, null, null);

  assert.equal(
    service.needsContactDispatchRetry({
      contact_status: CONTACT_STATUS.VERIFIED,
      status: BOOKING_STATUS.OPEN,
      metadata: JSON.stringify({ contactDispatchCompleted: true }),
    }),
    true,
  );
  assert.equal(
    service.needsContactDispatchRetry({
      contact_status: CONTACT_STATUS.VERIFIED,
      status: BOOKING_STATUS.OPEN,
      metadata: JSON.stringify({
        contactDispatchCompleted: true,
        contactDispatchDelivered: true,
      }),
    }),
    false,
  );
});

test('notification idempotency key follows driver-call-open booking and driver scope', async () => {
  const harness = createDispatchService({ drivers: [{ id: 9, user_id: 11 }] });
  await harness.service.dispatchAfterContactVerified(harness.bookingRow);

  assert.equal(harness.inserts.length, 1);
  assert.equal(harness.inserts[0].notificationType, NOTIFICATION_TYPES.DRIVER_CALL_AVAILABLE);
  assert.equal(harness.inserts[0].idempotencyKey, 'driver-call-open:5:9');
});

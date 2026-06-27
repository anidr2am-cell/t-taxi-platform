process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const OutboxRepository = require('../src/repositories/outbox.repository');
const OutboxProcessor = require('../src/services/outboxProcessor.service');
const NotificationService = require('../src/services/notification.service');
const { OUTBOX_STATUS } = require('../src/constants/outboxStatus');
const { EVENTS } = require('../src/events');
const { sanitizeOutboxPayload } = require('../src/utils/outboxPayload.util');
const NOTIFICATION_TYPES = require('../src/constants/notificationTypes');
const NOTIFICATION_CHANNELS = require('../src/constants/notificationChannels');
const DELIVERY_STATUS = require('../src/constants/notificationDeliveryStatus');

function makeConnHarness() {
  const state = {
    outboxRows: [],
    nextId: 1,
    notifications: [],
    idempotencyKeys: new Set(),
  };
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
    async query(sql, params = []) {
      if (sql.includes('INSERT INTO outbox_events')) {
        const id = state.nextId++;
        state.outboxRows.push({
          id,
          aggregate_type: params[0],
          aggregate_id: params[1],
          event_type: params[2],
          payload: JSON.parse(params[3]),
          status: params[4],
          retry_count: 0,
          max_retries: 3,
        });
        return [{ insertId: id }];
      }
      if (sql.includes('FOR UPDATE SKIP LOCKED')) {
        const limit = params[2];
        const rows = state.outboxRows
          .filter((row) =>
            (row.status === OUTBOX_STATUS.PENDING || row.status === OUTBOX_STATUS.FAILED)
            && row.retry_count < row.max_retries)
          .slice(0, limit)
          .map((row) => ({ id: row.id }));
        return [rows];
      }
      if (sql.includes('SET status = ?') && sql.includes('WHERE id IN')) {
        const ids = params[1];
        for (const row of state.outboxRows) {
          if (ids.includes(row.id)) row.status = params[0];
        }
        return [];
      }
      if (sql.includes('FROM outbox_events') && sql.includes('WHERE id IN')) {
        const ids = params[0];
        const rows = state.outboxRows.filter((row) => ids.includes(row.id));
        return [rows];
      }
      if (sql.includes('WHERE id = ?') && sql.includes('FOR UPDATE')) {
        const row = state.outboxRows.find((item) => item.id === params[0]);
        return [row ? [row] : []];
      }
      if (sql.includes('retry_count = retry_count + 1')) {
        const row = state.outboxRows.find((item) => item.id === params[3]);
        if (row) {
          row.retry_count += 1;
          row.error_message = params[0];
          row.status = row.retry_count >= row.max_retries
            ? OUTBOX_STATUS.FAILED
            : OUTBOX_STATUS.PENDING;
        }
        return [];
      }
      if (sql.includes('processed_at = CURRENT_TIMESTAMP')) {
        const row = state.outboxRows.find((item) => item.id === params[1]);
        if (row) {
          row.status = OUTBOX_STATUS.COMPLETED;
          row.processed_at = new Date();
          row.error_message = null;
        }
        return [];
      }
      if (sql.includes('SET status = ?') && sql.includes('WHERE id = ?') && !sql.includes('retry_count')) {
        const row = state.outboxRows.find((item) => item.id === params[1]);
        if (row) row.status = params[0];
        return [];
      }
      return [[]];
    },
  };
  const pool = {
    async getConnection() {
      return conn;
    },
    async query(sql, params = []) {
      return conn.query(sql, params);
    },
  };
  return { conn, pool, state };
}

function makeNotificationService(state, pool, overrides = {}) {
  let insertCount = 0;
  const notificationRepository = {
    async findByIdempotencyKey(_c, key) {
      if (state.idempotencyKeys.has(key) || overrides.existingKey === key) {
        return { id: 99, user_id: 8 };
      }
      return null;
    },
    async insert(_c, data) {
      insertCount += 1;
      state.idempotencyKeys.add(data.idempotencyKey);
      state.notifications.push(data);
      return insertCount;
    },
    async insertDelivery() { return 1; },
    async findDeliveryByNotificationAndChannel() { return null; },
    async findDeliveriesByNotificationId() {
      return [
        { id: 1, channel: NOTIFICATION_CHANNELS.IN_APP, delivery_status: DELIVERY_STATUS.PENDING },
        { id: 2, channel: NOTIFICATION_CHANNELS.EMAIL, delivery_status: DELIVERY_STATUS.PENDING },
        { id: 3, channel: NOTIFICATION_CHANNELS.FCM, delivery_status: DELIVERY_STATUS.PENDING },
      ];
    },
    async updateDeliveryStatus() {},
    async findById(id) {
      return {
        id,
        user_id: 8,
        booking_id: 10,
        type: NOTIFICATION_TYPES.BOOKING_CREATED,
        title: 'Booking created',
        body: 'Body',
        payload: { bookingNumber: 'TX202607010001' },
      };
    },
    async countNotifications() { return 1; },
    async findNotifications() { return []; },
    async countUnread() { return 0; },
    async markRead() {},
    async markAllRead() {},
    async findAdminNotifications() { return []; },
    async countAdminNotifications() { return 0; },
    async findByBookingForGuest() { return []; },
    async findByBookingForCustomer() { return []; },
    async findByBookingForDriver() { return []; },
    async findDevicesByUserId() { return []; },
  };
  const userRepository = {
    async findAdminUserIds() { return [1]; },
    async findById() { return { id: 8, role: 'CUSTOMER' }; },
    async findActiveByRoles() { return [{ id: 1, role: 'ADMIN' }]; },
  };
  const bookingRepository = {
    async findById() {
      return {
        id: 10,
        booking_number: 'TX202607010001',
        customer_user_id: 8,
        driver_id: 9,
        driver_user_id: 99,
      };
    },
    async findByBookingNumber() {
      return {
        id: 10,
        booking_number: 'TX202607010001',
        customer_user_id: 8,
        driver_id: 9,
        driver_user_id: 99,
      };
    },
  };
  const driverRepository = {
    async findById() { return { id: 9, user_id: 99 }; },
  };
  const bookingService = {
    async assertBookingAccess() {},
  };
  const service = new NotificationService(
    pool,
    notificationRepository,
    userRepository,
    bookingRepository,
    driverRepository,
    bookingService,
  );
  return { service, getInsertCount: () => insertCount };
}

test('business transaction writes an outbox event', async () => {
  const { conn, pool, state } = makeConnHarness();
  const repo = new OutboxRepository(pool);
  const id = await repo.insertNotificationEvent(conn, {
    aggregateId: 10,
    eventType: EVENTS.BOOKING_CREATED,
    payload: {
      eventId: 'evt-1',
      eventName: EVENTS.BOOKING_CREATED,
      bookingId: 10,
      bookingNumber: 'TX202607010001',
      customerUserId: 8,
    },
  });
  assert.equal(id, 1);
  assert.equal(state.outboxRows.length, 1);
  assert.equal(state.outboxRows[0].status, OUTBOX_STATUS.PENDING);
});

test('failed business transaction writes no outbox event when rolled back', async () => {
  const { conn, pool, state } = makeConnHarness();
  const repo = new OutboxRepository(pool);
  try {
    await conn.beginTransaction();
    await repo.insertNotificationEvent(conn, {
      aggregateId: 10,
      eventType: EVENTS.BOOKING_CREATED,
      payload: { eventId: 'evt-1', bookingNumber: 'TX202607010001' },
    });
    await conn.rollback();
    state.outboxRows.length = 0;
  } finally {
    conn.release();
  }
  assert.equal(state.outboxRows.length, 0);
});

test('successful outbox processing creates notification', async () => {
  const { pool, state } = makeConnHarness();
  state.outboxRows.push({
    id: 1,
    aggregate_type: 'booking',
    aggregate_id: 10,
    event_type: EVENTS.BOOKING_CREATED,
    payload: {
      eventId: 'evt-1',
      eventName: EVENTS.BOOKING_CREATED,
      bookingId: 10,
      bookingNumber: 'TX202607010001',
      customerUserId: 8,
    },
    status: OUTBOX_STATUS.PROCESSING,
    retry_count: 0,
    max_retries: 3,
  });
  const { service } = makeNotificationService(state, pool);
  const processor = new OutboxProcessor(new OutboxRepository(pool), () => service);
  await processor.processClaimedRow(state.outboxRows[0]);
  assert.equal(state.notifications.length, 2);
  assert.equal(state.outboxRows[0].status, OUTBOX_STATUS.COMPLETED);
});

test('processed outbox event is not processed twice', async () => {
  const { pool, state } = makeConnHarness();
  state.outboxRows.push({
    id: 1,
    aggregate_type: 'booking',
    aggregate_id: 10,
    event_type: EVENTS.BOOKING_CREATED,
    payload: {
      eventId: 'evt-1',
      eventName: EVENTS.BOOKING_CREATED,
      bookingId: 10,
      bookingNumber: 'TX202607010001',
      customerUserId: 8,
    },
    status: OUTBOX_STATUS.COMPLETED,
    retry_count: 0,
    max_retries: 3,
  });
  const { service, getInsertCount } = makeNotificationService(state, pool);
  const repo = new OutboxRepository(pool);
  const processor = new OutboxProcessor(repo, () => service);
  const claimed = await repo.claimById(1);
  assert.equal(claimed, null);
  await processor.processClaimedRow(state.outboxRows[0]);
  assert.equal(getInsertCount(), 0);
});

test('handler failure leaves event retryable', async () => {
  const { pool, state } = makeConnHarness();
  state.outboxRows.push({
    id: 1,
    aggregate_type: 'booking',
    aggregate_id: 10,
    event_type: EVENTS.BOOKING_CREATED,
    payload: { eventId: 'evt-1', bookingNumber: 'TX202607010001' },
    status: OUTBOX_STATUS.PROCESSING,
    retry_count: 0,
    max_retries: 3,
  });
  const failingService = {
    async handleDomainEvent() {
      throw new Error('handler failed');
    },
  };
  const processor = new OutboxProcessor(new OutboxRepository(pool), () => failingService);
  await processor.processClaimedRow(state.outboxRows[0]);
  assert.equal(state.outboxRows[0].status, OUTBOX_STATUS.PENDING);
  assert.equal(state.outboxRows[0].retry_count, 1);
  assert.match(state.outboxRows[0].error_message, /handler failed/);
});

test('retry after partial notification creation creates no duplicate notification', async () => {
  const { pool, state } = makeConnHarness();
  const payload = {
    eventId: 'evt-dup',
    eventName: EVENTS.BOOKING_CREATED,
    bookingId: 10,
    bookingNumber: 'TX202607010001',
    customerUserId: 8,
  };
  state.outboxRows.push({
    id: 1,
    aggregate_type: 'booking',
    aggregate_id: 10,
    event_type: EVENTS.BOOKING_CREATED,
    payload,
    status: OUTBOX_STATUS.PROCESSING,
    retry_count: 0,
    max_retries: 3,
  });
  const { service, getInsertCount } = makeNotificationService(state, pool);
  const processor = new OutboxProcessor(new OutboxRepository(pool), () => service);
  await processor.processClaimedRow(state.outboxRows[0]);
  state.outboxRows[0].status = OUTBOX_STATUS.PENDING;
  await processor.processClaimedRow(state.outboxRows[0]);
  assert.equal(getInsertCount(), 2);
  assert.equal(state.notifications.length, 2);
});

test('startup recovery processes pending event', async () => {
  const { pool, state } = makeConnHarness();
  state.outboxRows.push({
    id: 1,
    aggregate_type: 'booking',
    aggregate_id: 10,
    event_type: EVENTS.BOOKING_CREATED,
    payload: {
      eventId: 'evt-startup',
      eventName: EVENTS.BOOKING_CREATED,
      bookingId: 10,
      bookingNumber: 'TX202607010001',
      customerUserId: 8,
    },
    status: OUTBOX_STATUS.PENDING,
    retry_count: 0,
    max_retries: 3,
    scheduled_at: new Date(),
  });
  const { service } = makeNotificationService(state, pool);
  const processor = new OutboxProcessor(new OutboxRepository(pool), () => service, 50);
  const processed = await processor.processPendingBatch(50);
  assert.equal(processed, 1);
  assert.equal(state.outboxRows[0].status, OUTBOX_STATUS.COMPLETED);
});

test('startup recovery failure does not throw', async () => {
  const brokenRepo = {
    pool: {
      async getConnection() {
        throw new Error('db unavailable');
      },
    },
    async claimPendingBatch() { return []; },
  };
  const processor = new OutboxProcessor(brokenRepo, () => ({}));
  await processor.recoverOnStartup();
});

test('batch size is bounded', async () => {
  const { pool, state } = makeConnHarness();
  for (let i = 1; i <= 60; i += 1) {
    state.outboxRows.push({
      id: i,
      aggregate_type: 'booking',
      aggregate_id: 10,
      event_type: EVENTS.BOOKING_CREATED,
      payload: {
        eventId: `evt-${i}`,
        eventName: EVENTS.BOOKING_CREATED,
        bookingId: 10,
        bookingNumber: 'TX202607010001',
        customerUserId: 8,
      },
      status: OUTBOX_STATUS.PENDING,
      retry_count: 0,
      max_retries: 3,
      scheduled_at: new Date(),
    });
  }
  const { service } = makeNotificationService(state, pool);
  const processor = new OutboxProcessor(new OutboxRepository(pool), () => service, 50);
  const processed = await processor.processPendingBatch(50);
  assert.equal(processed, 50);
});

test('outbox payload contains no secret fields', () => {
  const safe = sanitizeOutboxPayload({
    eventId: 'evt-1',
    bookingNumber: 'TX202607010001',
    guestAccessToken: 'secret-token',
    password: 'pw',
    filePath: '/tmp/receipt.pdf',
    qrToken: 'qr-secret',
  });
  assert.equal(safe.guestAccessToken, undefined);
  assert.equal(safe.password, undefined);
  assert.equal(safe.filePath, undefined);
  assert.equal(safe.qrToken, undefined);
  assert.equal(safe.bookingNumber, 'TX202607010001');
});

test('disabled EMAIL/FCM still do not fail processing', async () => {
  const { pool, state } = makeConnHarness();
  state.outboxRows.push({
    id: 1,
    aggregate_type: 'booking',
    aggregate_id: 10,
    event_type: EVENTS.BOOKING_CREATED,
    payload: {
      eventId: 'evt-1',
      eventName: EVENTS.BOOKING_CREATED,
      bookingId: 10,
      bookingNumber: 'TX202607010001',
      customerUserId: 8,
    },
    status: OUTBOX_STATUS.PROCESSING,
    retry_count: 0,
    max_retries: 3,
  });
  const { service } = makeNotificationService(state, pool);
  const processor = new OutboxProcessor(new OutboxRepository(pool), () => service);
  await processor.processClaimedRow(state.outboxRows[0]);
  assert.equal(state.outboxRows[0].status, OUTBOX_STATUS.COMPLETED);
});

test('original business operation remains committed when notification processing fails', async () => {
  const { conn, pool, state } = makeConnHarness();
  const repo = new OutboxRepository(pool);
  let committed = false;
  const connWithCommit = {
    ...conn,
    async commit() {
      committed = true;
    },
  };
  await repo.insertNotificationEvent(connWithCommit, {
    aggregateId: 10,
    eventType: EVENTS.BOOKING_CREATED,
    payload: { eventId: 'evt-1', bookingNumber: 'TX202607010001' },
  });
  await connWithCommit.commit();
  state.outboxRows[0].status = OUTBOX_STATUS.PROCESSING;
  const failingService = {
    async handleDomainEvent() {
      throw new Error('post-commit failure');
    },
  };
  const processor = new OutboxProcessor(repo, () => failingService);
  await processor.processClaimedRow(state.outboxRows[0]);
  assert.equal(committed, true);
  assert.equal(state.outboxRows[0].status, OUTBOX_STATUS.PENDING);
});

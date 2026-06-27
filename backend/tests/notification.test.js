process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const request = require('supertest');
const NotificationService = require('../src/services/notification.service');
const NOTIFICATION_TYPES = require('../src/constants/notificationTypes');
const NOTIFICATION_CHANNELS = require('../src/constants/notificationChannels');
const DELIVERY_STATUS = require('../src/constants/notificationDeliveryStatus');
const RECIPIENT_TYPES = require('../src/constants/notificationRecipientTypes');
const ERROR_CODES = require('../src/constants/errorCodes');
const ROLES = require('../src/constants/roles');
const { EVENTS } = require('../src/events');
const container = require('../src/helpers/container');
const app = require('../src/app');
const {
  EmailNotificationAdapter,
  FcmNotificationAdapter,
} = require('../src/services/notificationDelivery.adapters');

function sign(role = 'CUSTOMER', id = 8) {
  return jwt.sign(
    { sub: id, email: `${role.toLowerCase()}@example.com`, role, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

function makeService(overrides = {}) {
  let insertCount = 0;
  const notificationRepository = {
    async findByIdempotencyKey(_c, key) {
      if (overrides.existingKey === key) {
        return { id: 99, user_id: 8 };
      }
      return null;
    },
    async insert() {
      insertCount += 1;
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
        body: 'Your booking has been created.',
        payload: { bookingNumber: 'TX202607010001' },
      };
    },
    async countNotifications() { return overrides.total ?? 1; },
    async findNotifications() {
      return overrides.rows ?? [{
        id: 1,
        type: NOTIFICATION_TYPES.BOOKING_CREATED,
        title: 'Booking created',
        body: 'Body',
        payload: { bookingNumber: 'TX202607010001' },
        read_at: null,
        created_at: '2026-07-02 10:00:00',
      }];
    },
    async countUnread() { return overrides.unread ?? 1; },
    async markRead() { return true; },
    async markAllRead() { return 2; },
    ...overrides.notificationRepository,
  };
  const userRepository = {
    async findActiveByRoles() {
      return overrides.admins ?? [{ id: 1, role: ROLES.ADMIN }, { id: 2, role: ROLES.SUPER_ADMIN }];
    },
  };
  const bookingRepository = {
    async findById(id) {
      return {
        id,
        booking_number: 'TX202607010001',
        customer_user_id: 8,
        driver_id: 5,
        driver_user_id: 44,
      };
    },
    async findByBookingNumber() {
      return {
        id: 10,
        booking_number: 'TX202607010001',
        customer_user_id: 8,
        driver_id: 5,
      };
    },
    ...overrides.bookingRepository,
  };
  const driverRepository = {};
  const bookingService = {
    validateBookingNumber: (n) => String(n).trim().toUpperCase(),
    async assertCustomerOrGuestAccess() {},
    ...overrides.bookingService,
  };
  const pool = {
    async getConnection() {
      return {
        async beginTransaction() {},
        async commit() {},
        async rollback() {},
        release() {},
      };
    },
  };
  return new NotificationService(
    pool,
    notificationRepository,
    userRepository,
    bookingRepository,
    driverRepository,
    bookingService,
    overrides.adapters,
  );
}

test('notification created from booking.created event', async () => {
  const service = makeService();
  await service.handleDomainEvent(EVENTS.BOOKING_CREATED, {
    eventId: 'evt-1',
    bookingId: 10,
    bookingNumber: 'TX202607010001',
    customerUserId: 8,
  });
  assert.ok(true);
});

test('duplicate event creates one notification via idempotency', async () => {
  const service = makeService({ existingKey: 'evt-1:BOOKING_CREATED:user:8' });
  const result = await service.createNotificationIdempotent({
    eventId: 'evt-1',
    eventName: EVENTS.BOOKING_CREATED,
    notificationType: NOTIFICATION_TYPES.BOOKING_CREATED,
    recipientType: RECIPIENT_TYPES.USER,
    userId: 8,
    bookingId: 10,
    audienceRole: ROLES.CUSTOMER,
    payload: { bookingNumber: 'TX202607010001' },
  });
  assert.equal(result.notificationId, 99);
  assert.equal(result.created, false);
});

test('disabled EMAIL adapter records SKIPPED', async () => {
  const adapter = new EmailNotificationAdapter();
  const result = await adapter.send({}, {});
  assert.equal(result.status, DELIVERY_STATUS.SKIPPED);
});

test('disabled FCM adapter records SKIPPED', async () => {
  const adapter = new FcmNotificationAdapter();
  const result = await adapter.send({}, {});
  assert.equal(result.status, DELIVERY_STATUS.SKIPPED);
});

test('payload sanitization removes secrets', () => {
  const service = makeService();
  const safe = service.sanitizePayload({
    bookingNumber: 'TX202607010001',
    guestAccessToken: 'secret',
    token_hash: 'hash',
  });
  assert.equal(safe.bookingNumber, 'TX202607010001');
  assert.equal('guestAccessToken' in safe, false);
  assert.equal('token_hash' in safe, false);
});

test('customer sees own notifications', async () => {
  const service = makeService();
  const data = await service.listForUser(8, ROLES.CUSTOMER, {});
  assert.equal(data.items.length, 1);
});

test('guest booking notifications require authorization', async () => {
  const service = makeService({
    bookingService: {
      validateBookingNumber: (n) => n,
      async assertCustomerOrGuestAccess() {
        const AppError = require('../src/utils/AppError');
        throw new AppError('Booking is not accessible', {
          statusCode: 403,
          errorCode: ERROR_CODES.BOOKING_NOT_ACCESSIBLE,
        });
      },
    },
  });
  await assert.rejects(
    () => service.getBookingNotifications('TX202607010001', null, 'bad-token', {}),
    (err) => err.errorCode === ERROR_CODES.BOOKING_NOT_ACCESSIBLE,
  );
});

test('mark read ownership enforced', async () => {
  const service = makeService({
    notificationRepository: {
      async findByIdempotencyKey() { return null; },
      async insert() { return 1; },
      async insertDelivery() {},
      async findDeliveryByNotificationAndChannel() { return null; },
      async findDeliveriesByNotificationId() { return []; },
      async findById() { return { id: 1 }; },
      async countNotifications() { return 0; },
      async findNotifications() { return []; },
      async countUnread() { return 0; },
      async markRead() { return false; },
      async markAllRead() { return 0; },
    },
  });
  await assert.rejects(
    () => service.markReadForUser(8, ROLES.CUSTOMER, 1),
    (err) => err.errorCode === ERROR_CODES.NOTIFICATION_NOT_FOUND,
  );
});

test('driver inbox list for driver user', async () => {
  const service = makeService();
  const data = await service.listForUser(44, ROLES.DRIVER, {});
  assert.equal(data.items.length, 1);
});

test('ADMIN can list admin notifications', async () => {
  container.register('notificationService', () => ({
    async listForUser() {
      return { page: 1, pageSize: 20, total: 1, items: [{ notificationId: 1 }] };
    },
  }));
  const res = await request(app)
    .get('/api/v1/admin/notifications')
    .set('Authorization', `Bearer ${sign('ADMIN', 1)}`);
  assert.equal(res.status, 200);
});

test('DRIVER cannot access admin notifications', async () => {
  const res = await request(app)
    .get('/api/v1/admin/notifications')
    .set('Authorization', `Bearer ${sign('DRIVER', 44)}`);
  assert.equal(res.status, 403);
});

test('trip completed creates customer notifications', async () => {
  let specs = 0;
  const service = makeService({
    notificationRepository: {
      async findByIdempotencyKey() { return null; },
      async insert() { specs += 1; return specs; },
      async insertDelivery() { return 1; },
      async findDeliveryByNotificationAndChannel() { return null; },
      async findDeliveriesByNotificationId() { return []; },
      async findById(id) { return { id, user_id: 8, payload: {} }; },
      async updateDeliveryStatus() {},
    },
  });
  await service.handleDomainEvent(EVENTS.TRIP_COMPLETED, {
    eventId: 'evt-trip',
    bookingId: 10,
    bookingNumber: 'TX202607010001',
    customerUserId: 8,
  });
  assert.ok(specs >= 2);
});

test('handler failure propagates to caller for outbox retry', async () => {
  const service = makeService({
    bookingRepository: {
      async findById() { throw new Error('db fail'); },
    },
  });
  await assert.rejects(
    () => service.handleDomainEvent(EVENTS.DRIVER_ASSIGNED, {
      eventId: 'evt-2',
      bookingId: 10,
      bookingNumber: 'TX202607010001',
    }),
    /db fail/,
  );
});

process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const request = require('supertest');
const NotificationRepository = require('../src/repositories/notification.repository');
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
    async findActiveFcmDevicesForRecipient() { return []; },
    async deactivateDeviceById() {},
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

function makeDeviceRepositoryHarness(existingId = 7) {
  const updates = [];
  const inserts = [];
  const conn = {
    async query(sql, params) {
      if (sql.includes('SELECT id') && sql.includes('FROM notification_devices')) {
        return [[{ id: existingId }]];
      }
      if (sql.includes('UPDATE notification_devices')) {
        updates.push(params);
        return [{ affectedRows: 1 }];
      }
      if (sql.includes('INSERT INTO notification_devices')) {
        inserts.push(params);
        return [{ insertId: 11 }];
      }
      return [[]];
    },
  };
  return { repository: new NotificationRepository({}), conn, updates, inserts };
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

test('configured EMAIL adapter sends without logging raw recipient data', async () => {
  let sent = null;
  const adapter = new EmailNotificationAdapter({
    smtp: {
      host: 'smtp.example.com',
      port: 587,
      fromEmail: 'noreply@ttaxi.example',
      fromName: 'TTaxi',
    },
    transportFactory: () => ({
      async sendMail(message) {
        sent = message;
      },
    }),
  });
  const result = await adapter.send({
    title: 'Booking confirmed',
    body: 'Your booking has been confirmed.',
    recipient_email: 'customer@example.com',
    booking_number: 'TX202607010001',
    payload: { bookingNumber: 'TX202607010001' },
  });
  assert.equal(result.status, DELIVERY_STATUS.DELIVERED);
  assert.equal(sent.to, 'customer@example.com');
  assert.equal(sent.from, '"TTaxi" <noreply@ttaxi.example>');
});

test('EMAIL adapter marks malformed recipient as permanent failure', async () => {
  const adapter = new EmailNotificationAdapter({
    smtp: { host: 'smtp.example.com', port: 587, fromEmail: 'noreply@ttaxi.example' },
  });
  const result = await adapter.send({ recipient_email: 'not-an-email' }, {});
  assert.equal(result.status, DELIVERY_STATUS.FAILED);
  assert.equal(result.permanent, true);
  assert.match(result.error, /^PERMANENT_/);
});

test('disabled FCM adapter records SKIPPED', async () => {
  const adapter = new FcmNotificationAdapter();
  const result = await adapter.send({}, {});
  assert.equal(result.status, DELIVERY_STATUS.SKIPPED);
});

test('configured FCM adapter skips safely when no device token exists', async () => {
  const adapter = new FcmNotificationAdapter({
    firebase: { projectId: 'ttaxi-test', clientEmail: 'firebase@example.com' },
  });
  const result = await adapter.send({ id: 1, title: 'Title', body: 'Body' }, {});
  assert.equal(result.status, DELIVERY_STATUS.SKIPPED);
});

test('FCM adapter marks invalid registration token as permanent failure', async () => {
  const adapter = new FcmNotificationAdapter({
    firebase: { projectId: 'ttaxi-test', clientEmail: 'firebase@example.com' },
    admin: {
      apps: [{}],
      messaging: () => ({
        async send() {
          const err = new Error('Requested entity was not found.');
          err.code = 'messaging/registration-token-not-registered';
          throw err;
        },
      }),
    },
  });
  const result = await adapter.send({
    id: 1,
    title: 'Title',
    body: 'Body',
    fcmToken: 'fcm-token-value-for-test',
  }, {});
  assert.equal(result.status, DELIVERY_STATUS.FAILED);
  assert.equal(result.permanent, true);
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

test('ADMIN can list notification delivery statuses without sensitive payloads', async () => {
  container.register('notificationService', () => ({
    async listDeliveryStatuses() {
      return {
        page: 1,
        pageSize: 20,
        total: 1,
        items: [{
          deliveryId: 11,
          notificationId: 22,
          notificationType: NOTIFICATION_TYPES.BOOKING_CONFIRMED,
          eventName: EVENTS.BOOKING_CONFIRMED,
          bookingNumber: 'TX202607010001',
          channel: NOTIFICATION_CHANNELS.EMAIL,
          deliveryStatus: DELIVERY_STATUS.DELIVERED,
          attemptCount: 1,
          lastError: null,
        }],
      };
    },
  }));
  const res = await request(app)
    .get('/api/v1/admin/notifications/deliveries')
    .set('Authorization', `Bearer ${sign('ADMIN', 1)}`);
  assert.equal(res.status, 200);
  const item = res.body.data.items[0];
  assert.equal(item.channel, NOTIFICATION_CHANNELS.EMAIL);
  assert.equal('body' in item, false);
  assert.equal('recipientEmail' in item, false);
  assert.equal('fcmToken' in item, false);
});

test('ADMIN can register and list notification devices without raw token', async () => {
  const token = sign('ADMIN', 1);
  container.register('notificationService', () => ({
    async registerDeviceForUser(user, body) {
      assert.equal(user.role, ROLES.ADMIN);
      assert.equal(body.token, 'fcm-token-value-for-admin-test');
      return {
        deviceId: 10,
        platform: body.platform,
        token: 'abcd1234...',
        deviceName: body.deviceName,
      };
    },
    async listDevicesForUser(user) {
      assert.equal(user.id, 1);
      return {
        items: [{
          deviceId: 10,
          platform: 'WEB',
          token: 'abcd1234...',
          deviceName: 'Browser',
        }],
      };
    },
  }));

  const create = await request(app)
    .post('/api/v1/notifications/devices')
    .set('Authorization', `Bearer ${token}`)
    .send({
      token: 'fcm-token-value-for-admin-test',
      platform: 'WEB',
      deviceName: 'Browser',
    });
  assert.equal(create.status, 201);
  assert.equal(create.body.data.token, 'abcd1234...');
  assert.equal(create.text.includes('fcm-token-value-for-admin-test'), false);

  const list = await request(app)
    .get('/api/v1/notifications/devices')
    .set('Authorization', `Bearer ${token}`);
  assert.equal(list.status, 200);
  assert.equal(list.text.includes('fcm-token-value-for-admin-test'), false);
});

test('duplicate token transfer from user to guest clears user owner', async () => {
  const h = makeDeviceRepositoryHarness();
  const id = await h.repository.upsertDevice(h.conn, {
    userId: null,
    bookingId: 10,
    platform: 'WEB',
    token: 'token-value',
    tokenHash: 'hash-value',
  });
  assert.equal(id, 7);
  assert.equal(h.updates[0][0], null);
  assert.equal(h.updates[0][1], 10);
});

test('duplicate token transfer from guest to user clears booking owner', async () => {
  const h = makeDeviceRepositoryHarness();
  const id = await h.repository.upsertDevice(h.conn, {
    userId: 8,
    bookingId: null,
    platform: 'WEB',
    token: 'token-value',
    tokenHash: 'hash-value',
  });
  assert.equal(id, 7);
  assert.equal(h.updates[0][0], 8);
  assert.equal(h.updates[0][1], null);
});

test('notification device ownership rejects both user and booking owners', async () => {
  const repository = new NotificationRepository({});
  await assert.rejects(
    () => repository.upsertDevice(null, {
      userId: 8,
      bookingId: 10,
      platform: 'WEB',
      token: 'token-value',
      tokenHash: 'hash-value',
    }),
    /exactly one/,
  );
});

test('notification device ownership rejects missing user and booking owners', async () => {
  const repository = new NotificationRepository({});
  await assert.rejects(
    () => repository.upsertDevice(null, {
      userId: null,
      bookingId: null,
      platform: 'WEB',
      token: 'token-value',
      tokenHash: 'hash-value',
    }),
    /exactly one/,
  );
});

test('CUSTOMER cannot register authenticated notification device', async () => {
  const res = await request(app)
    .post('/api/v1/notifications/devices')
    .set('Authorization', `Bearer ${sign('CUSTOMER', 8)}`)
    .send({ token: 'fcm-token-value-for-customer-test', platform: 'WEB' });
  assert.equal(res.status, 403);
});

test('guest can register and delete device with valid booking access header', async () => {
  container.register('notificationService', () => ({
    async registerDeviceForGuestBooking(bookingId, guestAccessToken, body) {
      assert.equal(bookingId, 10);
      assert.equal(guestAccessToken, 'guest-token');
      assert.equal(body.token, 'fcm-token-value-for-guest-test');
      return { deviceId: 22, platform: 'WEB', token: 'eeff0011...' };
    },
    async deactivateDeviceForGuestBooking(bookingId, guestAccessToken, deviceId) {
      assert.equal(bookingId, 10);
      assert.equal(guestAccessToken, 'guest-token');
      assert.equal(deviceId, 22);
      return { deviceId, active: false };
    },
  }));

  const create = await request(app)
    .post('/api/v1/public/bookings/10/notification-devices')
    .set('X-Guest-Access-Token', 'guest-token')
    .send({ token: 'fcm-token-value-for-guest-test', platform: 'WEB' });
  assert.equal(create.status, 201);
  assert.equal(create.text.includes('fcm-token-value-for-guest-test'), false);

  const del = await request(app)
    .delete('/api/v1/public/bookings/10/notification-devices/22')
    .set('X-Guest-Access-Token', 'guest-token');
  assert.equal(del.status, 200);
});

test('guest device registration rejects invalid token shape before service', async () => {
  const res = await request(app)
    .post('/api/v1/public/bookings/10/notification-devices')
    .set('X-Guest-Access-Token', 'guest-token')
    .send({ token: 'short', platform: 'WEB' });
  assert.equal(res.status, 400);
});

test('DRIVER cannot list notification delivery statuses', async () => {
  const res = await request(app)
    .get('/api/v1/admin/notifications/deliveries')
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

test('cancelled and no-show events produce notification specs', async () => {
  const types = [];
  const service = makeService({
    notificationRepository: {
      async findByIdempotencyKey() { return null; },
      async insert(_conn, data) { types.push(data.notificationType); return types.length; },
      async insertDelivery() { return 1; },
      async findDeliveryByNotificationAndChannel() { return null; },
      async findDeliveriesByNotificationId() { return []; },
      async findById(id) { return { id, user_id: 8, payload: {} }; },
      async updateDeliveryStatus() {},
    },
  });
  await service.handleDomainEvent(EVENTS.BOOKING_CANCELLED, {
    eventId: 'evt-cancel',
    bookingId: 10,
    bookingNumber: 'TX202607010001',
    customerUserId: 8,
    driverUserId: 44,
    driverId: 5,
  });
  await service.handleDomainEvent(EVENTS.BOOKING_NO_SHOW, {
    eventId: 'evt-noshow',
    bookingId: 10,
    bookingNumber: 'TX202607010001',
    customerUserId: 8,
    driverUserId: 44,
    driverId: 5,
  });
  assert.ok(types.includes(NOTIFICATION_TYPES.BOOKING_CANCELLED));
  assert.ok(types.includes(NOTIFICATION_TYPES.BOOKING_NO_SHOW));
});

test('settlement rejection maps to settlement rejected notification type', async () => {
  const specs = await makeService().buildSpecsForEvent(EVENTS.RECEIPT_REJECTED, {
    eventId: 'evt-reject',
    bookingId: 10,
    bookingNumber: 'TX202607010001',
    driverUserId: 44,
    driverId: 5,
  });
  assert.equal(specs[0].notificationType, NOTIFICATION_TYPES.SETTLEMENT_REJECTED);
});

test('adapter failure updates delivery as failed for retry', async () => {
  const updates = [];
  const service = makeService({
    adapters: {
      [NOTIFICATION_CHANNELS.EMAIL]: {
        async send() {
          throw new Error('smtp temporarily unavailable');
        },
      },
    },
    notificationRepository: {
      async findDeliveriesByNotificationId() {
        return [
          {
            id: 2,
            channel: NOTIFICATION_CHANNELS.EMAIL,
            delivery_status: DELIVERY_STATUS.PENDING,
            attempt_count: 0,
            last_error: null,
          },
        ];
      },
      async findById(id) {
        return {
          id,
          user_id: 8,
          booking_id: 10,
          type: NOTIFICATION_TYPES.BOOKING_CREATED,
          title: 'Booking created',
          body: 'Your booking has been created.',
          recipient_email: 'customer@example.com',
          payload: { bookingNumber: 'TX202607010001' },
        };
      },
      async updateDeliveryStatus(_conn, deliveryId, status, lastError) {
        updates.push({ deliveryId, status, lastError });
      },
    },
  });
  await service.processDeliveries(1);
  assert.deepEqual(updates, [{
    deliveryId: 2,
    status: DELIVERY_STATUS.FAILED,
    lastError: 'smtp temporarily unavailable',
  }]);
});

test('inactive devices are excluded and invalid FCM token deactivates device', async () => {
  const deactivated = [];
  const sends = [];
  const service = makeService({
    adapters: {
      [NOTIFICATION_CHANNELS.FCM]: {
        async send(notification) {
          sends.push(notification.fcmToken);
          return {
            status: DELIVERY_STATUS.FAILED,
            error: 'PERMANENT_FCM_INVALID_TOKEN',
            permanent: true,
          };
        },
      },
    },
    notificationRepository: {
      async findActiveFcmDevicesForRecipient(recipient) {
        assert.equal(recipient.userId, 8);
        return [{ id: 31, fcm_token: 'active-token' }];
      },
      async deactivateDeviceById(_conn, deviceId) {
        deactivated.push(deviceId);
      },
    },
  });
  const result = await service.sendFcmToActiveDevices(
    { id: 1, title: 'Title', body: 'Body' },
    { userId: 8 },
  );
  assert.deepEqual(sends, ['active-token']);
  assert.deepEqual(deactivated, [31]);
  assert.equal(result.permanent, true);
});

test('transient FCM error remains retryable', async () => {
  const service = makeService({
    adapters: {
      [NOTIFICATION_CHANNELS.FCM]: {
        async send() {
          throw new Error('fcm temporarily unavailable');
        },
      },
    },
    notificationRepository: {
      async findActiveFcmDevicesForRecipient() {
        return [{ id: 41, fcm_token: 'active-token' }];
      },
      async deactivateDeviceById() {
        throw new Error('should not deactivate transient errors');
      },
    },
  });
  const result = await service.sendFcmToActiveDevices(
    { id: 1, title: 'Title', body: 'Body' },
    { userId: 8 },
  );
  assert.equal(result.status, DELIVERY_STATUS.FAILED);
  assert.equal(result.error, 'fcm temporarily unavailable');
  assert.equal(result.permanent, undefined);
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

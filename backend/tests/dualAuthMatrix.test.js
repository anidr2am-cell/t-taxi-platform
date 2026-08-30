process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';
process.env.SOCIAL_TOKEN_ENCRYPTION_KEY = process.env.SOCIAL_TOKEN_ENCRYPTION_KEY
  || Buffer.alloc(32, 3).toString('base64');

const { test } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const request = require('supertest');

const app = require('../src/app');
const container = require('../src/helpers/container');
const ERROR_CODES = require('../src/constants/errorCodes');
const ROLES = require('../src/constants/roles');
const BOOKING_STATUS = require('../src/constants/reservationStatus');
const NotificationService = require('../src/services/notification.service');
const ReviewService = require('../src/services/review.service');
const BookingStatusService = require('../src/services/bookingStatus.service');
const GuestVehiclePhotoService = require('../src/services/guestVehiclePhoto.service');
const DriverLocationService = require('../src/services/driverLocation.service');
const NOTIFICATION_TYPES = require('../src/constants/notificationTypes');
const RECIPIENT_TYPES = require('../src/constants/notificationRecipientTypes');
const MODERATION_STATUS = require('../src/constants/reviewModerationStatus');
const { hashToken } = require('../src/utils/tokenHash.util');

function signCustomer(id = 42, expiresIn = '1h') {
  return jwt.sign(
    { sub: id, email: 'customer@example.com', role: ROLES.CUSTOMER, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn },
  );
}

function bookingRow(overrides = {}) {
  return {
    id: 10,
    booking_number: 'TX202607010001',
    status: BOOKING_STATUS.DRIVER_ASSIGNED,
    customer_user_id: null,
    driver_id: 7,
    driver_user_id: 44,
    scheduled_pickup_at: '2026-07-25 15:00:00',
    ...overrides,
  };
}

function completedBookingRow(overrides = {}) {
  return bookingRow({
    status: BOOKING_STATUS.COMPLETED,
    ...overrides,
  });
}

function assertAccessError(promise) {
  return assert.rejects(
    promise,
    (err) => err.errorCode === ERROR_CODES.BOOKING_NOT_ACCESSIBLE,
  );
}

function buildPhotoService({ customerUserId = null } = {}) {
  const fileRow = {
    file_path: 'driver-applications/vehicle-photo.jpg',
    mime_type: 'image/jpeg',
    original_filename: 'vehicle-photo.jpg',
  };
  return new GuestVehiclePhotoService({
    async findGuestAssignedDriverVehiclePhotoFile(bookingId, tokenHash) {
      if (bookingId === 10 && tokenHash === hashToken('guest-token')) {
        return fileRow;
      }
      return null;
    },
    async findAssignedDriverVehiclePhotoFileByBookingId(bookingId) {
      return bookingId === 10 ? fileRow : null;
    },
    async findById(bookingId) {
      return bookingId === 10 ? bookingRow({ customer_user_id: customerUserId }) : null;
    },
  }, {
    async assertCustomerOrGuestAccess(_conn, row, authUser, guestAccessToken) {
      if (
        authUser?.role === ROLES.CUSTOMER
        && row.customer_user_id
        && row.customer_user_id === authUser.id
      ) {
        return;
      }
      if (String(guestAccessToken ?? '').trim()) {
        return;
      }
      const err = new Error('Booking is not accessible');
      err.errorCode = ERROR_CODES.BOOKING_NOT_ACCESSIBLE;
      throw err;
    },
  }, {
    async getConnection() {
      return { release() {} };
    },
  });
}

function buildLocationService({ customerUserId = null } = {}) {
  const locationRow = {
    booking_number: 'TX202607010001',
    booking_status: 'ON_ROUTE',
    driver_id: 7,
    driver_name: 'Somchai',
    current_lat: 12.9,
    current_lng: 100.8,
    location_updated_at: new Date().toISOString(),
  };
  return new DriverLocationService(
    { async getConnection() { return { release() {} }; } },
    {
      async findAssignedDriverLocationByBookingId(bookingId) {
        return bookingId === 10 ? locationRow : null;
      },
      async findGuestAssignedDriverLocation(bookingId, tokenHash) {
        if (bookingId === 10 && tokenHash === hashToken('guest-token')) {
          return locationRow;
        }
        return null;
      },
    },
    {
      async findById(bookingId) {
        return bookingId === 10 ? bookingRow({ customer_user_id: customerUserId }) : null;
      },
    },
    {
      async assertCustomerOrGuestAccess(_conn, row, authUser, guestAccessToken) {
        if (
          authUser?.role === ROLES.CUSTOMER
          && row.customer_user_id
          && row.customer_user_id === authUser.id
        ) {
          return;
        }
        if (String(guestAccessToken ?? '').trim()) {
          return;
        }
        const err = new Error('Booking is not accessible');
        err.errorCode = ERROR_CODES.BOOKING_NOT_ACCESSIBLE;
        throw err;
      },
    },
  );
}

function buildNotificationService({ customerUserId = null } = {}) {
  return new NotificationService(
    { async getConnection() { return { release() {} }; } },
    {
      async findNotifications(filters) {
        if (filters.recipientType === RECIPIENT_TYPES.GUEST_BOOKING) {
          return [{
            id: 1,
            type: NOTIFICATION_TYPES.DRIVER_ASSIGNED,
            title: 'Guest channel',
            body: 'Body',
            payload: {},
            read_at: null,
            created_at: '2026-07-02 10:00:00',
          }];
        }
        return [{
          id: 2,
          type: NOTIFICATION_TYPES.BOOKING_CONFIRMED,
          title: 'User channel',
          body: 'Body',
          payload: {},
          read_at: null,
          created_at: '2026-07-02 11:00:00',
        }];
      },
      async countNotifications() { return 1; },
      async countUnread() { return 0; },
      async markRead() { return true; },
      async markAllRead() { return 0; },
      async findByIdempotencyKey() { return null; },
      async insert() { return 1; },
      async insertDelivery() {},
      async findDeliveryByNotificationAndChannel() { return null; },
      async findDeliveriesByNotificationId() { return []; },
      async findById(id) { return { id }; },
      async deactivateDeviceById() {},
      async findActiveFcmDevicesForRecipient() { return []; },
    },
    {},
    {
      async findByBookingNumber() {
        return bookingRow({ customer_user_id: customerUserId });
      },
    },
    {},
    {
      validateBookingNumber: (n) => String(n).trim().toUpperCase(),
      async assertCustomerOrGuestAccess() {},
    },
  );
}

function buildReviewService({ customerUserId = null } = {}) {
  const bookingRepository = {
    async findByBookingNumberForUpdate() {
      return completedBookingRow({ customer_user_id: customerUserId });
    },
    async findActiveGuestTokenForBooking(_conn, _bookingId, tokenHash) {
      return tokenHash === hashToken('guest-token') ? { id: 1 } : null;
    },
    async insertActivityLog() {},
  };
  const reviewRepository = {
    async findByBookingIdForUpdate() { return null; },
    async insert() { return 1; },
    async findByBookingId() {
      return {
        id: 1,
        rating: 5,
        comment: null,
        tags: [],
        moderation_status: MODERATION_STATUS.VISIBLE,
      };
    },
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
  return new ReviewService(
    pool,
    bookingRepository,
    reviewRepository,
    { async findByUserId() { return { id: 7 }; } },
    {
      validateBookingNumber: (n) => String(n).trim().toUpperCase(),
      async assertCustomerOrGuestAccess(_conn, row, authUser, guestAccessToken) {
        if (
          authUser?.role === ROLES.CUSTOMER
          && row.customer_user_id
          && row.customer_user_id === authUser.id
        ) {
          return;
        }
        if (String(guestAccessToken ?? '').trim()) {
          return;
        }
        const err = new Error('Booking is not accessible');
        err.errorCode = ERROR_CODES.BOOKING_NOT_ACCESSIBLE;
        throw err;
      },
    },
    null,
    null,
  );
}

function buildCancelService({ customerUserId = null } = {}) {
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };
  const repository = {
    async findByBookingNumberForUpdate() {
      return bookingRow({
        customer_user_id: customerUserId,
        status: BOOKING_STATUS.DRIVER_ASSIGNED,
      });
    },
    async updateStatus() {},
    async insertStatusLog() {},
    async insertActivityLog() {},
    async clearAssignmentOnCancel() {
      return { id: 1, driver_id: 7 };
    },
    async findActiveGuestTokenForBooking(_conn, _bookingId, tokenHash) {
      return tokenHash === hashToken('guest-token') ? { id: 1 } : null;
    },
  };
  return new BookingStatusService(
    { async getConnection() { return conn; } },
    repository,
    { async insertNotificationEvent() { return 1; } },
    { async dispatchOutboxIds() {} },
  );
}

function registerDriverLocationService(service) {
  container.register('driverLocationService', () => service);
}

const cancelNowMs = Date.parse('2026-07-25T13:00:00+07:00') - 1000;

test('dual-auth matrix cancel: guest only', async () => {
  const service = buildCancelService();
  const result = await service.cancelByCustomer(
    'TX202607010001',
    { guestAccessToken: 'guest-token' },
    null,
    { nowMs: cancelNowMs },
  );
  assert.equal(result.status, BOOKING_STATUS.CANCELLED);
});

test('dual-auth matrix cancel: JWT owner', async () => {
  const service = buildCancelService({ customerUserId: 42 });
  const result = await service.cancelByCustomer(
    'TX202607010001',
    {},
    { id: 42, role: ROLES.CUSTOMER },
    { nowMs: cancelNowMs },
  );
  assert.equal(result.status, BOOKING_STATUS.CANCELLED);
});

test('dual-auth matrix cancel: JWT + guest unclaimed', async () => {
  const service = buildCancelService({ customerUserId: null });
  const result = await service.cancelByCustomer(
    'TX202607010001',
    { guestAccessToken: 'guest-token' },
    { id: 42, role: ROLES.CUSTOMER },
    { nowMs: cancelNowMs },
  );
  assert.equal(result.status, BOOKING_STATUS.CANCELLED);
});

test('dual-auth matrix cancel: expired JWT + valid guest (authUser null)', async () => {
  const service = buildCancelService({ customerUserId: null });
  const result = await service.cancelByCustomer(
    'TX202607010001',
    { guestAccessToken: 'guest-token' },
    null,
    { nowMs: cancelNowMs },
  );
  assert.equal(result.status, BOOKING_STATUS.CANCELLED);
});

test('dual-auth matrix review: guest only', async () => {
  const service = buildReviewService();
  const data = await service.submitBookingReview(
    'TX202607010001',
    { rating: 5, guestAccessToken: 'guest-token' },
    null,
  );
  assert.equal(data.submitted, true);
});

test('dual-auth matrix review: JWT owner', async () => {
  const service = buildReviewService({ customerUserId: 42 });
  const data = await service.submitBookingReview(
    'TX202607010001',
    { rating: 5 },
    { id: 42, role: ROLES.CUSTOMER },
  );
  assert.equal(data.submitted, true);
});

test('dual-auth matrix review: JWT + guest unclaimed', async () => {
  const service = buildReviewService({ customerUserId: null });
  const data = await service.submitBookingReview(
    'TX202607010001',
    { rating: 5, guestAccessToken: 'guest-token' },
    { id: 42, role: ROLES.CUSTOMER },
  );
  assert.equal(data.submitted, true);
});

test('dual-auth matrix review: expired JWT + valid guest (authUser null)', async () => {
  const service = buildReviewService({ customerUserId: null });
  const data = await service.submitBookingReview(
    'TX202607010001',
    { rating: 5, guestAccessToken: 'guest-token' },
    null,
  );
  assert.equal(data.submitted, true);
});

test('dual-auth matrix notify: guest only', async () => {
  const service = buildNotificationService({ customerUserId: null });
  const data = await service.getBookingNotifications(
    'TX202607010001',
    null,
    'guest-token',
    {},
  );
  assert.equal(data.items[0].title, 'Guest channel');
});

test('dual-auth matrix notify: JWT owner merges channels', async () => {
  const service = buildNotificationService({ customerUserId: 42 });
  const data = await service.getBookingNotifications(
    'TX202607010001',
    { id: 42, role: ROLES.CUSTOMER },
    null,
    {},
  );
  assert.equal(data.total, 2);
});

test('dual-auth matrix notify: JWT + guest unclaimed', async () => {
  const service = buildNotificationService({ customerUserId: null });
  const data = await service.getBookingNotifications(
    'TX202607010001',
    { id: 42, role: ROLES.CUSTOMER },
    'guest-token',
    {},
  );
  assert.equal(data.items[0].title, 'Guest channel');
});

test('dual-auth matrix notify: expired JWT + valid guest (authUser null)', async () => {
  const service = buildNotificationService({ customerUserId: null });
  const data = await service.getBookingNotifications(
    'TX202607010001',
    null,
    'guest-token',
    {},
  );
  assert.equal(data.items[0].title, 'Guest channel');
});

test('dual-auth matrix photo: guest only', async () => {
  const service = buildPhotoService({ customerUserId: null });
  const file = await service.getAssignedDriverVehiclePhotoFile(10, 'guest-token', null);
  assert.equal(file.mimeType, 'image/jpeg');
});

test('dual-auth matrix photo: JWT owner', async () => {
  const service = buildPhotoService({ customerUserId: 42 });
  const file = await service.getAssignedDriverVehiclePhotoFile(
    10,
    null,
    { id: 42, role: ROLES.CUSTOMER },
  );
  assert.equal(file.mimeType, 'image/jpeg');
});

test('dual-auth matrix photo: JWT + guest unclaimed', async () => {
  const service = buildPhotoService({ customerUserId: null });
  const file = await service.getAssignedDriverVehiclePhotoFile(
    10,
    'guest-token',
    { id: 42, role: ROLES.CUSTOMER },
  );
  assert.equal(file.mimeType, 'image/jpeg');
});

test('dual-auth matrix photo: expired JWT + valid guest route fallback', async () => {
  container.register('guestVehiclePhotoService', () => buildPhotoService({ customerUserId: null }));
  const res = await request(app)
    .get('/api/v1/public/bookings/10/assigned-driver-vehicle-photo')
    .set('Authorization', `Bearer ${signCustomer(42, '-1h')}`)
    .set('X-Guest-Access-Token', 'guest-token');
  assert.equal(res.statusCode, 200);
});

test('dual-auth matrix location: guest only', async () => {
  const service = buildLocationService({ customerUserId: null });
  const result = await service.getDriverLocation(10, { guestAccessToken: 'guest-token' });
  assert.equal(result.available, true);
});

test('dual-auth matrix location: JWT owner', async () => {
  const service = buildLocationService({ customerUserId: 42 });
  const result = await service.getDriverLocation(10, {
    authUser: { id: 42, role: ROLES.CUSTOMER },
  });
  assert.equal(result.available, true);
});

test('dual-auth matrix location: JWT + guest unclaimed', async () => {
  const service = buildLocationService({ customerUserId: null });
  const result = await service.getDriverLocation(10, {
    authUser: { id: 42, role: ROLES.CUSTOMER },
    guestAccessToken: 'guest-token',
  });
  assert.equal(result.available, true);
});

test('dual-auth matrix location: expired JWT + valid guest route fallback', async () => {
  registerDriverLocationService(buildLocationService({ customerUserId: null }));
  const res = await request(app)
    .get('/api/v1/public/bookings/10/driver-location')
    .set('Authorization', `Bearer ${signCustomer(42, '-1h')}`)
    .set('X-Guest-Access-Token', 'guest-token');
  assert.equal(res.statusCode, 200);
});

test('dual-auth matrix rejects JWT non-owner without guest token for photo', async () => {
  const service = buildPhotoService({ customerUserId: 42 });
  await assertAccessError(
    service.getAssignedDriverVehiclePhotoFile(10, null, { id: 99, role: ROLES.CUSTOMER }),
  );
});

test('dual-auth matrix rejects JWT non-owner without guest token for location', async () => {
  const service = buildLocationService({ customerUserId: 42 });
  await assertAccessError(
    service.getDriverLocation(10, {
      authUser: { id: 99, role: ROLES.CUSTOMER },
      guestAccessToken: null,
    }),
  );
});

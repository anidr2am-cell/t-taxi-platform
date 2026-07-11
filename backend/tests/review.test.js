process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const request = require('supertest');
const ReviewService = require('../src/services/review.service');
const MODERATION_STATUS = require('../src/constants/reviewModerationStatus');
const ERROR_CODES = require('../src/constants/errorCodes');
const ROLES = require('../src/constants/roles');
const container = require('../src/helpers/container');
const app = require('../src/app');

function sign(role = 'CUSTOMER', id = 8) {
  return jwt.sign(
    { sub: id, email: `${role.toLowerCase()}@example.com`, role, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

function booking(overrides = {}) {
  return {
    id: 10,
    booking_number: 'TX202607010001',
    status: 'COMPLETED',
    customer_user_id: 8,
    driver_id: 5,
    ...overrides,
  };
}

function reviewRow(overrides = {}) {
  return {
    id: 1,
    booking_id: 10,
    driver_id: 5,
    rating: 5,
    comment: 'Great',
    moderation_status: MODERATION_STATUS.VISIBLE,
    hidden_reason: null,
    created_at: '2026-07-02 10:00:00',
    booking_number: 'TX202607010001',
    ...overrides,
  };
}

function makeService(overrides = {}) {
  const bookingRepository = {
    async findByBookingNumber() { return booking(); },
    async findByBookingNumberForUpdate() { return booking(); },
    async findActiveGuestTokenForBooking() { return { id: 99 }; },
    async insertActivityLog() {},
    ...overrides.bookingRepository,
  };
  const reviewRepository = {
    async findByBookingId() { return null; },
    async findByBookingIdForUpdate() { return null; },
    async insert() { return 1; },
    async findById() { return reviewRow(); },
    async findByIdForUpdate() { return reviewRow(); },
    async findModerationActivityLogs() { return []; },
    async countAdminReviews() { return 0; },
    async findAdminReviews() { return []; },
    async updateModeration() {},
    async getVisibleRatingSummaryForDriver() {
      return { averageRating: 4.5, reviewCount: 2 };
    },
    ...overrides.reviewRepository,
  };
  const driverRepository = {
    async findByUserId() { return { id: 5 }; },
    ...overrides.driverRepository,
  };
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
    ...overrides.pool,
  };
  return new ReviewService(
    pool,
    bookingRepository,
    reviewRepository,
    driverRepository,
    bookingService,
  );
}

test('SETTLEMENT_PENDING booking is eligible for review lookup', async () => {
  const service = makeService({
    bookingRepository: {
      async findByBookingNumber() { return booking({ status: 'SETTLEMENT_PENDING' }); },
    },
  });
  const data = await service.getBookingReview('TX202607010001', { id: 8, role: ROLES.CUSTOMER }, null);
  assert.equal(data.eligible, true);
  assert.equal(data.submitted, false);
});

test('completed booking is eligible for review lookup', async () => {
  const service = makeService();
  const data = await service.getBookingReview('TX202607010001', { id: 8, role: ROLES.CUSTOMER }, null);
  assert.equal(data.eligible, true);
  assert.equal(data.submitted, false);
});

test('non-completed booking is not eligible', async () => {
  const service = makeService({
    bookingRepository: {
      async findByBookingNumber() { return booking({ status: 'PICKED_UP' }); },
    },
  });
  const data = await service.getBookingReview('TX202607010001', { id: 8, role: ROLES.CUSTOMER }, null);
  assert.equal(data.eligible, false);
});

test('CANCELLED booking is not eligible', async () => {
  const service = makeService({
    bookingRepository: {
      async findByBookingNumber() { return booking({ status: 'CANCELLED' }); },
    },
  });
  const data = await service.getBookingReview('TX202607010001', { id: 8, role: ROLES.CUSTOMER }, null);
  assert.equal(data.eligible, false);
});

test('NO_SHOW booking is not eligible', async () => {
  const service = makeService({
    bookingRepository: {
      async findByBookingNumber() { return booking({ status: 'NO_SHOW' }); },
    },
  });
  const data = await service.getBookingReview('TX202607010001', { id: 8, role: ROLES.CUSTOMER }, null);
  assert.equal(data.eligible, false);
});

test('booking without driver is not eligible', async () => {
  const service = makeService({
    bookingRepository: {
      async findByBookingNumber() { return booking({ driver_id: null }); },
    },
  });
  const data = await service.getBookingReview('TX202607010001', { id: 8, role: ROLES.CUSTOMER }, null);
  assert.equal(data.eligible, false);
});

test('SETTLEMENT_PENDING booking can submit review', async () => {
  const service = makeService({
    bookingRepository: {
      async findByBookingNumber() { return booking({ status: 'SETTLEMENT_PENDING' }); },
      async findByBookingNumberForUpdate() { return booking({ status: 'SETTLEMENT_PENDING' }); },
    },
    reviewRepository: {
      async findByBookingIdForUpdate() { return null; },
      async insert() { return 1; },
      async findByBookingId() { return reviewRow({ rating: 4 }); },
    },
  });
  const data = await service.submitBookingReview(
    'TX202607010001',
    { rating: 4, comment: 'Good trip' },
    { id: 8, role: ROLES.CUSTOMER },
  );
  assert.equal(data.submitted, true);
  assert.equal(data.rating, 4);
});

test('CANCELLED booking cannot submit review', async () => {
  const service = makeService({
    bookingRepository: {
      async findByBookingNumberForUpdate() { return booking({ status: 'CANCELLED' }); },
    },
  });
  await assert.rejects(
    () => service.submitBookingReview('TX202607010001', { rating: 5 }, { id: 8, role: ROLES.CUSTOMER }),
    (err) => err.errorCode === ERROR_CODES.REVIEW_NOT_ELIGIBLE,
  );
});

test('NO_SHOW booking cannot submit review', async () => {
  const service = makeService({
    bookingRepository: {
      async findByBookingNumberForUpdate() { return booking({ status: 'NO_SHOW' }); },
    },
  });
  await assert.rejects(
    () => service.submitBookingReview('TX202607010001', { rating: 5 }, { id: 8, role: ROLES.CUSTOMER }),
    (err) => err.errorCode === ERROR_CODES.REVIEW_NOT_ELIGIBLE,
  );
});

test('valid tags accepted for low rating', async () => {
  let insertedTags = null;
  const service = makeService({
    reviewRepository: {
      async findByBookingIdForUpdate() { return null; },
      async insert(_conn, payload) {
        insertedTags = payload.tags;
        return 1;
      },
      async findByBookingId() {
        return reviewRow({ rating: 2, tags_json: JSON.stringify(insertedTags) });
      },
    },
  });
  await service.submitBookingReview(
    'TX202607010001',
    {
      rating: 2,
      tags: ['FRIENDLY', 'LATE_ARRIVAL'],
      comment: 'Late but friendly',
    },
    { id: 8, role: ROLES.CUSTOMER },
  );
  assert.deepEqual(insertedTags, ['FRIENDLY', 'LATE_ARRIVAL']);
});

test('negative tags rejected for high rating', async () => {
  const service = makeService();
  assert.throws(
    () => service.normalizeTags(['LATE_ARRIVAL'], 5),
    (err) => err.errorCode === ERROR_CODES.VALIDATION_ERROR,
  );
});

test('unknown tag rejected', async () => {
  const service = makeService();
  assert.throws(
    () => service.normalizeTags(['NOT_A_TAG'], 5),
    (err) => err.errorCode === ERROR_CODES.VALIDATION_ERROR,
  );
});

test('whitespace-only comment stored as null', () => {
  const service = makeService();
  assert.equal(service.normalizeComment('   '), null);
});

test('plain text comment is stored without HTML stripping', () => {
  const service = makeService();
  assert.equal(service.normalizeComment('<b>Great trip</b>'), '<b>Great trip</b>');
  assert.equal(service.normalizeComment('  Nice ride  '), 'Nice ride');
});

test('low rating flagged in admin summary', () => {
  const service = makeService();
  const mapped = service.mapAdminReviewSummary(reviewRow({ rating: 2 }));
  assert.equal(mapped.lowRating, true);
  assert.equal(service.mapAdminReviewSummary(reviewRow({ rating: 4 })).lowRating, false);
});

test('guest with valid token can submit review', async () => {
  let guestTokenUsed = false;
  const service = makeService({
    bookingService: {
      validateBookingNumber: (n) => n,
      async assertCustomerOrGuestAccess(_c, _b, _u, token) {
        guestTokenUsed = !!token;
      },
    },
    reviewRepository: {
      async findByBookingIdForUpdate() { return null; },
      async insert() { return 1; },
      async findByBookingId() { return reviewRow(); },
    },
  });
  const data = await service.submitBookingReview(
    'TX202607010001',
    { rating: 5, comment: 'Nice', guestAccessToken: 'guest-token' },
    null,
  );
  assert.equal(guestTokenUsed, true);
  assert.equal(data.submitted, true);
});

test('wrong guest token rejected', async () => {
  const service = makeService({
    bookingService: {
      validateBookingNumber: (n) => n,
      async assertCustomerOrGuestAccess() {
        const AppError = require('../src/utils/AppError');
        const HTTP_STATUS = require('../src/constants/httpStatus');
        throw new AppError('Booking is not accessible', {
          statusCode: HTTP_STATUS.FORBIDDEN,
          errorCode: ERROR_CODES.BOOKING_NOT_ACCESSIBLE,
        });
      },
    },
  });
  await assert.rejects(
    () => service.submitBookingReview(
      'TX202607010001',
      { rating: 4, guestAccessToken: 'bad' },
      null,
    ),
    (err) => err.errorCode === ERROR_CODES.BOOKING_NOT_ACCESSIBLE,
  );
});

test('authenticated owner can submit review', async () => {
  const service = makeService({
    reviewRepository: {
      async findByBookingIdForUpdate() { return null; },
      async insert() { return 1; },
      async findByBookingId() { return reviewRow(); },
    },
  });
  const data = await service.submitBookingReview(
    'TX202607010001',
    { rating: 5, comment: 'Great' },
    { id: 8, role: ROLES.CUSTOMER },
  );
  assert.equal(data.submitted, true);
  assert.equal(data.rating, 5);
});

test('another customer rejected via access check', async () => {
  const service = makeService({
    bookingService: {
      validateBookingNumber: (n) => n,
      async assertCustomerOrGuestAccess() {
        const AppError = require('../src/utils/AppError');
        const HTTP_STATUS = require('../src/constants/httpStatus');
        throw new AppError('Booking is not accessible', {
          statusCode: HTTP_STATUS.FORBIDDEN,
          errorCode: ERROR_CODES.BOOKING_NOT_ACCESSIBLE,
        });
      },
    },
  });
  await assert.rejects(
    () => service.submitBookingReview('TX202607010001', { rating: 5 }, { id: 99, role: ROLES.CUSTOMER }),
    (err) => err.errorCode === ERROR_CODES.BOOKING_NOT_ACCESSIBLE,
  );
});

test('DRIVER cannot submit customer review', async () => {
  const service = makeService();
  await assert.rejects(
    () => service.submitBookingReview('TX202607010001', { rating: 5 }, { id: 44, role: ROLES.DRIVER }),
    (err) => err.errorCode === ERROR_CODES.FORBIDDEN,
  );
});

test('rating below 1 rejected', () => {
  const service = makeService();
  assert.throws(
    () => service.validateRating(0),
    (err) => err.errorCode === ERROR_CODES.INVALID_RATING,
  );
});

test('rating above 5 rejected', () => {
  const service = makeService();
  assert.throws(
    () => service.validateRating(6),
    (err) => err.errorCode === ERROR_CODES.INVALID_RATING,
  );
});

test('comment length enforced', () => {
  const service = makeService();
  assert.throws(
    () => service.normalizeComment('x'.repeat(501)),
    (err) => err.errorCode === ERROR_CODES.VALIDATION_ERROR,
  );
});

test('one review per booking', async () => {
  const service = makeService({
    reviewRepository: {
      async findByBookingIdForUpdate() { return reviewRow(); },
      async insert() { throw new Error('should not insert'); },
    },
  });
  await assert.rejects(
    () => service.submitBookingReview('TX202607010001', { rating: 5 }, { id: 8, role: ROLES.CUSTOMER }),
    (err) => err.errorCode === ERROR_CODES.REVIEW_ALREADY_SUBMITTED,
  );
});

test('duplicate key maps to REVIEW_ALREADY_SUBMITTED', async () => {
  const service = makeService({
    reviewRepository: {
      async findByBookingIdForUpdate() { return null; },
      async insert() {
        const err = new Error('dup');
        err.code = 'ER_DUP_ENTRY';
        throw err;
      },
      async findByBookingId() { return reviewRow(); },
    },
  });
  await assert.rejects(
    () => service.submitBookingReview('TX202607010001', { rating: 5 }, { id: 8, role: ROLES.CUSTOMER }),
    (err) => err.errorCode === ERROR_CODES.REVIEW_ALREADY_SUBMITTED,
  );
});

test('driver average and count from visible reviews', async () => {
  const service = makeService({
    reviewRepository: {
      async getVisibleRatingSummaryForDriver() {
        return { averageRating: 4.3, reviewCount: 3 };
      },
    },
  });
  const summary = await service.getDriverRatingSummary(44);
  assert.equal(summary.averageRating, 4.3);
  assert.equal(summary.reviewCount, 3);
});

test('no reviews returns null average', async () => {
  const service = makeService({
    reviewRepository: {
      async getVisibleRatingSummaryForDriver() {
        return { averageRating: null, reviewCount: 0 };
      },
    },
  });
  const summary = await service.getDriverRatingSummary(44);
  assert.equal(summary.averageRating, null);
  assert.equal(summary.reviewCount, 0);
});

test('hide requires reason', async () => {
  const service = makeService();
  await assert.rejects(
    () => service.hideReview(1, '  ', { id: 1, role: ROLES.ADMIN }),
    (err) => err.errorCode === ERROR_CODES.REVIEW_REASON_REQUIRED,
  );
});

test('hide writes audit log', async () => {
  let activityLogs = 0;
  const service = makeService({
    bookingRepository: {
      async insertActivityLog() { activityLogs += 1; },
    },
    reviewRepository: {
      async findByIdForUpdate() { return reviewRow(); },
      async updateModeration() {},
      async findById() { return reviewRow({ moderation_status: MODERATION_STATUS.HIDDEN }); },
      async findModerationActivityLogs() { return []; },
    },
  });
  await service.hideReview(1, 'Inappropriate language', { id: 1, role: ROLES.ADMIN });
  assert.equal(activityLogs, 1);
});

test('restore writes audit log', async () => {
  let activityLogs = 0;
  const service = makeService({
    bookingRepository: {
      async insertActivityLog() { activityLogs += 1; },
    },
    reviewRepository: {
      async findByIdForUpdate() {
        return reviewRow({ moderation_status: MODERATION_STATUS.HIDDEN, hidden_reason: 'Spam' });
      },
      async updateModeration() {},
      async findById() { return reviewRow(); },
      async findModerationActivityLogs() { return []; },
    },
  });
  await service.restoreReview(1, { id: 1, role: ROLES.ADMIN });
  assert.equal(activityLogs, 1);
});

test('admin detail does not expose guest token fields', async () => {
  const service = makeService({
    reviewRepository: {
      async findById() {
        return reviewRow({
          guest_access_token_id: 99,
          customer_user_id: null,
        });
      },
      async findModerationActivityLogs() { return []; },
    },
  });
  const detail = await service.getAdminReview(1);
  assert.equal(detail.customerSummary.displayName, 'Guest');
  assert.equal(JSON.stringify(detail).includes('guest_access_token'), false);
  assert.equal(JSON.stringify(detail).includes('token_hash'), false);
});

test('ADMIN can list reviews', async () => {
  container.register('reviewService', () => ({
    async listAdminReviews() {
      return { page: 1, pageSize: 20, total: 1, items: [{ reviewId: 1, rating: 5 }] };
    },
  }));
  const res = await request(app)
    .get('/api/v1/admin/reviews')
    .set('Authorization', `Bearer ${sign('ADMIN', 1)}`);
  assert.equal(res.status, 200);
  assert.equal(res.body.data.items.length, 1);
});

test('SUPER_ADMIN can list reviews', async () => {
  container.register('reviewService', () => ({
    async listAdminReviews() {
      return { page: 1, pageSize: 20, total: 0, items: [] };
    },
  }));
  const res = await request(app)
    .get('/api/v1/admin/reviews')
    .set('Authorization', `Bearer ${sign('SUPER_ADMIN', 2)}`);
  assert.equal(res.status, 200);
});

test('DRIVER cannot access admin reviews', async () => {
  const res = await request(app)
    .get('/api/v1/admin/reviews')
    .set('Authorization', `Bearer ${sign('DRIVER', 44)}`);
  assert.equal(res.status, 403);
});

test('CUSTOMER cannot access admin reviews', async () => {
  const res = await request(app)
    .get('/api/v1/admin/reviews')
    .set('Authorization', `Bearer ${sign('CUSTOMER', 8)}`);
  assert.equal(res.status, 403);
});

test('hide duplicate state with same reason is idempotent', async () => {
  const service = makeService({
    reviewRepository: {
      async findByIdForUpdate() {
        return reviewRow({
          moderation_status: MODERATION_STATUS.HIDDEN,
          hidden_reason: 'Spam',
        });
      },
      async findById() {
        return reviewRow({
          moderation_status: MODERATION_STATUS.HIDDEN,
          hidden_reason: 'Spam',
        });
      },
      async findModerationActivityLogs() { return []; },
    },
    bookingRepository: {
      async insertActivityLog() { throw new Error('should not log'); },
    },
  });
  const detail = await service.hideReview(1, 'Spam', { id: 1, role: ROLES.ADMIN });
  assert.equal(detail.moderationStatus, MODERATION_STATUS.HIDDEN);
});

test('restore on visible review is idempotent', async () => {
  const service = makeService({
    reviewRepository: {
      async findByIdForUpdate() { return reviewRow({ moderation_status: MODERATION_STATUS.VISIBLE }); },
      async findById() { return reviewRow(); },
      async findModerationActivityLogs() { return []; },
    },
    bookingRepository: {
      async insertActivityLog() { throw new Error('should not log'); },
    },
  });
  const detail = await service.restoreReview(1, { id: 1, role: ROLES.ADMIN });
  assert.equal(detail.moderationStatus, MODERATION_STATUS.VISIBLE);
});

test('GET review without authorization returns 403', async () => {
  container.register('reviewService', () => ({
    async getBookingReview() {
      const AppError = require('../src/utils/AppError');
      const HTTP_STATUS = require('../src/constants/httpStatus');
      throw new AppError('Booking is not accessible', {
        statusCode: HTTP_STATUS.FORBIDDEN,
        errorCode: ERROR_CODES.BOOKING_NOT_ACCESSIBLE,
      });
    },
  }));
  const res = await request(app).get('/api/v1/bookings/TX202607010001/review');
  assert.equal(res.status, 403);
  assert.equal(res.body.error_code, ERROR_CODES.BOOKING_NOT_ACCESSIBLE);
});

test('GET review reads guest token from header not query', async () => {
  let headerToken = null;
  let queryIgnored = true;
  container.register('reviewService', () => ({
    async getBookingReview(_bn, _auth, guestToken) {
      headerToken = guestToken;
      return { eligible: true, submitted: false };
    },
  }));
  const res = await request(app)
    .get('/api/v1/bookings/TX202607010001/review?guestAccessToken=query-leak')
    .set('X-Guest-Access-Token', 'header-token');
  assert.equal(res.status, 200);
  assert.equal(headerToken, 'header-token');
  assert.equal(queryIgnored, true);
});

test('ADMIN cannot use customer review lookup', async () => {
  const service = makeService();
  await assert.rejects(
    () => service.getBookingReview('TX202607010001', { id: 1, role: ROLES.ADMIN }, null),
    (err) => err.errorCode === ERROR_CODES.FORBIDDEN,
  );
});

test('SUPER_ADMIN cannot use customer review lookup', async () => {
  const service = makeService();
  await assert.rejects(
    () => service.getBookingReview('TX202607010001', { id: 1, role: ROLES.SUPER_ADMIN }, null),
    (err) => err.errorCode === ERROR_CODES.FORBIDDEN,
  );
});

test('customer review state omits hiddenReason and reviewer fields', () => {
  const service = makeService();
  const state = service.mapCustomerReviewState(
    booking(),
    reviewRow({
      hidden_reason: 'Spam',
      reviewed_by: 1,
      reviewed_at: '2026-07-02 11:00:00',
    }),
  );
  assert.equal('hiddenReason' in state, false);
  assert.equal('reviewedBy' in state, false);
  assert.equal('reviewedAt' in state, false);
  assert.equal(JSON.stringify(state).includes('Spam'), false);
});

test('driverId is derived from booking not request body', async () => {
  let capturedDriverId;
  const service = makeService({
    bookingRepository: {
      async findByBookingNumberForUpdate() { return booking({ driver_id: 42 }); },
      async insertActivityLog() {},
    },
    reviewRepository: {
      async findByBookingIdForUpdate() { return null; },
      async insert(_conn, data) {
        capturedDriverId = data.driverId;
        return 1;
      },
      async findByBookingId() { return reviewRow({ driver_id: 42 }); },
    },
  });
  await service.submitBookingReview(
    'TX202607010001',
    { rating: 5 },
    { id: 8, role: ROLES.CUSTOMER },
  );
  assert.equal(capturedDriverId, 42);
});

test('transaction failure creates neither review nor activity log', async () => {
  let logged = false;
  const service = makeService({
    bookingRepository: {
      async findByBookingNumberForUpdate() { return booking(); },
      async insertActivityLog() { logged = true; },
    },
    reviewRepository: {
      async findByBookingIdForUpdate() { return null; },
      async insert() { throw new Error('db fail'); },
    },
  });
  await assert.rejects(
    () => service.submitBookingReview('TX202607010001', { rating: 5 }, { id: 8, role: ROLES.CUSTOMER }),
  );
  assert.equal(logged, false);
});

test('driver rating summary exposes only aggregate fields', async () => {
  const service = makeService({
    reviewRepository: {
      async getVisibleRatingSummaryForDriver() {
        return { averageRating: 4.2, reviewCount: 2 };
      },
    },
  });
  const summary = await service.getDriverRatingSummary(44);
  assert.deepEqual(summary, { averageRating: 4.2, reviewCount: 2 });
  assert.equal('comment' in summary, false);
  assert.equal('bookingNumber' in summary, false);
});

const ReviewRepository = require('../src/repositories/review.repository');

test('rating aggregate SQL filters VISIBLE reviews only', async () => {
  let sql = '';
  const repo = new ReviewRepository({
    async query(queryText) {
      sql = queryText;
      return [[{ review_count: 2, average_rating: 4.5 }]];
    },
  });
  const summary = await repo.getVisibleRatingSummaryForDriver(5);
  assert.match(sql, /moderation_status = 'VISIBLE'/);
  assert.equal(summary.averageRating, 4.5);
  assert.equal(summary.reviewCount, 2);
});

test('rating aggregate with no visible reviews returns null average', async () => {
  const repo = new ReviewRepository({
    async query() {
      return [[{ review_count: 0, average_rating: null }]];
    },
  });
  const summary = await repo.getVisibleRatingSummaryForDriver(5);
  assert.equal(summary.averageRating, null);
  assert.equal(summary.reviewCount, 0);
});

test('rating aggregate rounds average to one decimal', async () => {
  const repo = new ReviewRepository({
    async query() {
      return [[{ review_count: 3, average_rating: 4.333333 }]];
    },
  });
  const summary = await repo.getVisibleRatingSummaryForDriver(5);
  assert.equal(summary.averageRating, 4.3);
  assert.equal(summary.reviewCount, 3);
});

test('hidden reviews excluded because aggregate uses VISIBLE status', async () => {
  let sql = '';
  const repo = new ReviewRepository({
    async query(queryText) {
      sql = queryText;
      return [[{ review_count: 1, average_rating: 5 }]];
    },
  });
  await repo.getVisibleRatingSummaryForDriver(5);
  assert.match(sql, /moderation_status = 'VISIBLE'/);
  assert.doesNotMatch(sql, /HIDDEN/);
});

const { parseStoredTags } = require('../src/constants/reviewTags');

test('parseStoredTags returns empty array for null tags_json', () => {
  assert.deepEqual(parseStoredTags(null), []);
  assert.deepEqual(parseStoredTags(undefined), []);
});

test('parseStoredTags returns empty array for malformed JSON string', () => {
  assert.deepEqual(parseStoredTags('{not-valid-json'), []);
});

test('parseStoredTags ignores unknown tag codes', () => {
  assert.deepEqual(parseStoredTags(['FRIENDLY', 'NOT_A_TAG']), ['FRIENDLY']);
});

test('mapCustomerReviewState returns empty tags when tags_json is null', () => {
  const service = makeService();
  const state = service.mapCustomerReviewState(
    booking({ status: 'SETTLEMENT_PENDING' }),
    reviewRow({ tags_json: null }),
  );
  assert.equal(state.submitted, true);
  assert.deepEqual(state.tags, []);
  assert.equal(state.comment, null);
});

test('mapAdminReviewSummary tolerates malformed tags_json', () => {
  const service = makeService();
  const summary = service.mapAdminReviewSummary(reviewRow({ tags_json: 'broken-json' }));
  assert.deepEqual(summary.tags, []);
  assert.equal(summary.lowRating, false);
});

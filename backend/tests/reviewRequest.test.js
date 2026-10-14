const { test } = require('node:test');
const assert = require('node:assert/strict');
const ReviewRequestService = require('../src/services/reviewRequest.service');
const BookingRepository = require('../src/repositories/booking.repository');
const { isBookingReviewEligible } = require('../src/utils/reviewEligibility.util');
const { reviewRequestState } = require('../src/utils/reviewRequest.util');
const { adminSettingsUpdateSchema } = require('../src/validators/platformSettings.validator');

function harness(overrides = {}) {
  const booking = { id: 1, driver_id: 2, status: 'SETTLEMENT_PENDING', metadata: { locale: 'th', reviewRequestEligibleAt: '2026-10-14T00:00:00.000Z', messengerType: 'KAKAO' }, ...overrides };
  const logs = [];
  const calls = [];
  const conn = { beginTransaction: async () => calls.push('begin'), commit: async () => calls.push('commit'), rollback: async () => calls.push('rollback'), release() {} };
  const repo = {
    findByBookingNumberForUpdate: async () => booking,
    updateCommissionFields: async (_conn, _id, fields) => { booking.metadata = fields.metadata; },
    insertActivityLog: async (_conn, _id, log) => logs.push(log),
  };
  return { service: new ReviewRequestService({ getConnection: async () => conn }, repo, { getPublic: async () => ({ googleReviewUrl: '' }) }), booking, logs, calls };
}
const actor = { id: 7, role: 'ADMIN', name: 'QA Admin' };

test('review eligibility includes both ended statuses and requires a driver; ratings never affect eligibility', () => {
  for (const status of ['SETTLEMENT_PENDING', 'COMPLETED']) {
    for (const rating of [1, 5, null]) assert.equal(isBookingReviewEligible({ status, driver_id: 2, rating }), true);
    assert.equal(isBookingReviewEligible({ status, driver_id: null }), false);
  }
  for (const status of ['OPEN', 'ON_ROUTE', 'PICKED_UP', 'CANCELLED', 'NO_SHOW']) assert.equal(isBookingReviewEligible({ status, driver_id: 2 }), false);
});
test('manual copy, send, confirmed resend and opt-out are independent from contact_status and preserve metadata', async () => {
  const h = harness();
  assert.equal((await h.service.get('TX202610140001')).status, 'NOT_REQUESTED');
  assert.equal((await h.service.update('TX202610140001', { action: 'COPY', locale: 'th' }, actor)).status, 'COPIED');
  assert.equal(h.booking.metadata.messengerType, 'KAKAO');
  assert.equal((await h.service.update('TX202610140001', { action: 'SENT', locale: 'th', channel: 'LINE' }, actor)).status, 'SENT');
  await assert.rejects(h.service.update('TX202610140001', { action: 'SENT', locale: 'th', channel: 'LINE' }, actor), { errorCode: 'REVIEW_REQUEST_ALREADY_SENT' });
  const sent = await h.service.update('TX202610140001', { action: 'SENT', locale: 'en', channel: 'EMAIL', confirmResend: true }, actor);
  assert.equal(sent.actorUserId, 7);
  assert.equal(sent.channel, 'EMAIL');
  await h.service.update('TX202610140001', { action: 'OPT_OUT', optedOut: true }, actor);
  await assert.rejects(h.service.update('TX202610140001', { action: 'COPY', locale: 'th' }, actor), { errorCode: 'REVIEW_REQUEST_OPTED_OUT' });
  assert.equal(h.logs.length, 4);
  assert.equal(Object.hasOwn(h.booking, 'contact_status'), false);
  assert.ok(h.calls.includes('rollback'));
});
test('request actions require an ended trip, explicit supported language and send channel', async () => {
  await assert.rejects(harness({ status: 'OPEN' }).service.update('X', { action: 'COPY', locale: 'ko' }, actor), { errorCode: 'REVIEW_NOT_ELIGIBLE' });
  await assert.rejects(harness().service.update('X', { action: 'COPY' }, actor), { errorCode: 'REVIEW_REQUEST_LOCALE_REQUIRED' });
  await assert.rejects(harness().service.update('X', { action: 'SENT', locale: 'ko', channel: 'unknown' }, actor), { errorCode: 'REVIEW_REQUEST_CHANNEL_REQUIRED' });
});
test('review queue requires a new trip-end marker, excludes sent and opted-out requests, and ignores view defaults', () => {
  const repo = new BookingRepository({});
  const filter = repo.buildAdminBookingFilters({ reviewRequestsOnly: true, needsActionOnly: true, serviceDateTo: '2000-01-01' });
  assert.match(filter.whereSql, /reviewRequestEligibleAt/);
  assert.match(filter.whereSql, /reviewRequest\.sentAt/);
  assert.match(filter.whereSql, /reviewRequest\.optedOut/);
  assert.doesNotMatch(filter.whereSql, /scheduled_pickup_at/);
  assert.equal(reviewRequestState({ status: 'COMPLETED', driver_id: 2 }).introduced, false);
});
test('google review URL accepts https only and empty values, rejecting unsafe schemes', () => {
  for (const url of ['https://g.page/r/abc/review', '', null]) assert.equal(adminSettingsUpdateSchema.validate({ googleReviewUrl: url }).error, undefined);
  for (const url of ['http://example.com', 'javascript:alert(1)', '//example.com']) assert.ok(adminSettingsUpdateSchema.validate({ googleReviewUrl: url }).error);
});
test('booking-time language overrides member locale and synchronizes it; guest language is saved', async () => {
  const queries = [];
  const conn = { query: async (sql, params) => { queries.push({ sql, params }); return [[{ locale: 'ko' }]]; } };
  const repo = new BookingRepository({});
  assert.equal(await repo.resolveBookingLocale(conn, 42, 'en'), 'en');
  assert.deepEqual(queries[1].params, ['en', 42]);
  assert.equal(await repo.resolveBookingLocale(conn, null, 'th'), 'th');
  assert.equal(queries.length, 2);
  assert.equal(await repo.resolveBookingLocale(conn, 42, undefined), 'ko');
});
test('new trip end marker is written once, atomically, without replacing other metadata', async () => {
  let sql;
  const repo = new BookingRepository({});
  await repo.markReviewRequestEligible({ query: async (value) => { sql = value; } }, 1, '2026-10-14T00:00:00Z');
  assert.match(sql, /JSON_SET/);
  assert.match(sql, /IS NULL/);
});

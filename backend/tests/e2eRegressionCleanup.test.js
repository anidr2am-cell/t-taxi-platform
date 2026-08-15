process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'tride_test';

const test = require('node:test');
const assert = require('node:assert/strict');

const runner = require('../scripts/staging-booking-regression');
const cleanup = require('../scripts/e2eRegressionCleanup');

const REGRESSION_MARKER = runner.REGRESSION_MARKER;

function regressionRecord(overrides = {}) {
  return {
    bookingNumber: overrides.bookingNumber ?? 'TX202608150013',
    payload: {
      customer: { name: '[E2E] Settlement Receipt Idempotency' },
      additionalRequests: REGRESSION_MARKER,
      ...overrides.payload,
    },
  };
}

function mockFetch(handlers) {
  const original = global.fetch;
  const calls = [];
  global.fetch = async (url, options = {}) => {
    calls.push({ url: String(url), options });
    for (const handler of handlers) {
      const result = handler(String(url), options);
      if (result != null) return result;
    }
    throw new Error(`Unexpected fetch: ${url}`);
  };
  return {
    calls,
    restore() {
      global.fetch = original;
    },
  };
}

function jsonResponse(body, status = 200) {
  return {
    ok: status >= 200 && status < 300,
    status,
    text: async () => JSON.stringify(body),
  };
}

test('receipt E2E payload uses accepted regression cleanup marker', () => {
  const receipt = require('../scripts/staging-receipt-idempotency-e2e');
  assert.ok(receipt);
  assert.equal(REGRESSION_MARKER, 'AUTOMATED_REGRESSION_TEST');
});

test('cleanup refuses non-E2E marker', async () => {
  const record = regressionRecord({ payload: { additionalRequests: 'RECEIPT_IDEMPOTENCY_E2E' } });
  const mock = mockFetch([
    (url) => {
      if (url.endsWith(`/api/v1/admin/bookings/${record.bookingNumber}`)) {
        return jsonResponse({
          success: true,
          data: {
            bookingNumber: record.bookingNumber,
            customer: record.payload.customer,
            specialRequests: 'RECEIPT_IDEMPOTENCY_E2E',
            status: 'OPEN',
          },
        });
      }
      return null;
    },
  ]);
  try {
    await assert.rejects(
      () => cleanup.teardownRegressionBooking('https://trider.taxi', {
        adminToken: 'admin-token',
        bookingNumber: record.bookingNumber,
        payload: record.payload,
      }),
      /without regression marker/,
    );
  } finally {
    mock.restore();
  }
});

test('cleanup refuses non-E2E customer name', async () => {
  const record = regressionRecord({ payload: { customer: { name: 'Real Customer' } } });
  const mock = mockFetch([
    (url) => {
      if (url.endsWith(`/api/v1/admin/bookings/${record.bookingNumber}`)) {
        return jsonResponse({
          success: true,
          data: {
            bookingNumber: record.bookingNumber,
            customer: { name: 'Real Customer' },
            specialRequests: REGRESSION_MARKER,
            status: 'OPEN',
          },
        });
      }
      return null;
    },
  ]);
  try {
    await assert.rejects(
      () => cleanup.teardownRegressionBooking('https://trider.taxi', {
        adminToken: 'admin-token',
        bookingNumber: record.bookingNumber,
        payload: record.payload,
      }),
      /Cleanup refused non-E2E booking/,
    );
  } finally {
    mock.restore();
  }
});

test('SETTLEMENT_PENDING cleanup approves receipt then archives', async () => {
  const record = regressionRecord({ bookingNumber: 'TX202608150016' });
  const calls = [];
  const mock = mockFetch([
    (url, options) => {
      calls.push({ url, method: options.method ?? 'GET' });
      if (url.endsWith(`/api/v1/admin/bookings/${record.bookingNumber}`)) {
        return jsonResponse({
          success: true,
          data: {
            bookingNumber: record.bookingNumber,
            customer: record.payload.customer,
            specialRequests: REGRESSION_MARKER,
            status: 'SETTLEMENT_PENDING',
            commissionReceiptFileId: 246,
          },
        });
      }
      if (url.endsWith(`/api/v1/admin/settlements/${record.bookingNumber}/approve`)) {
        return jsonResponse({ success: true, data: { bookingNumber: record.bookingNumber } });
      }
      if (url.endsWith('/api/v1/admin/bookings/archive')) {
        return jsonResponse({ success: true, data: { archived: 1 } });
      }
      return null;
    },
  ]);
  try {
    await cleanup.cleanupRegressionBookings('https://trider.taxi', {
      adminToken: 'admin-token',
      driverToken: 'driver-token',
      records: [record],
    });
    assert.ok(calls.some((call) => call.url.includes('/approve')));
    assert.ok(calls.some((call) => call.url.includes('/archive')));
  } finally {
    mock.restore();
  }
});

test('DRIVER_ASSIGNED cleanup unassigns before archive', async () => {
  const record = regressionRecord({ bookingNumber: 'TX202608150003' });
  const calls = [];
  const mock = mockFetch([
    (url, options) => {
      calls.push({ url, method: options.method ?? 'GET' });
      if (url.endsWith(`/api/v1/admin/bookings/${record.bookingNumber}`)) {
        return jsonResponse({
          success: true,
          data: {
            bookingNumber: record.bookingNumber,
            customer: record.payload.customer,
            specialRequests: REGRESSION_MARKER,
            status: 'DRIVER_ASSIGNED',
          },
        });
      }
      if (url.endsWith(`/api/v1/admin/bookings/${record.bookingNumber}/unassign-driver`)) {
        return jsonResponse({ success: true, data: { bookingNumber: record.bookingNumber } });
      }
      if (url.endsWith('/api/v1/admin/bookings/archive')) {
        return jsonResponse({ success: true, data: { archived: 1 } });
      }
      return null;
    },
  ]);
  try {
    await cleanup.cleanupRegressionBookings('https://trider.taxi', {
      adminToken: 'admin-token',
      records: [record],
    });
    assert.ok(calls.some((call) => call.url.includes('/unassign-driver')));
  } finally {
    mock.restore();
  }
});

test('OPEN booking cleanup archives without assignment teardown', async () => {
  const record = regressionRecord({ bookingNumber: 'TX202608150013' });
  const calls = [];
  const mock = mockFetch([
    (url, options) => {
      calls.push({ url, method: options.method ?? 'GET' });
      if (url.endsWith(`/api/v1/admin/bookings/${record.bookingNumber}`)) {
        return jsonResponse({
          success: true,
          data: {
            bookingNumber: record.bookingNumber,
            customer: record.payload.customer,
            specialRequests: REGRESSION_MARKER,
            status: 'OPEN',
          },
        });
      }
      if (url.endsWith('/api/v1/admin/bookings/archive')) {
        return jsonResponse({ success: true, data: { archived: 1 } });
      }
      return null;
    },
  ]);
  try {
    await cleanup.cleanupRegressionBookings('https://trider.taxi', {
      adminToken: 'admin-token',
      records: [record],
    });
    assert.equal(calls.filter((call) => call.url.includes('/unassign-driver')).length, 0);
    assert.equal(calls.filter((call) => call.url.includes('/approve')).length, 0);
  } finally {
    mock.restore();
  }
});

test('driver eligibility preflight fails when active jobs are saturated', async () => {
  const mock = mockFetch([
    (url) => {
      if (url.endsWith('/api/v1/admin/drivers')) {
        return jsonResponse({
          success: true,
          data: {
            items: [{
              displayName: '[E2E] Regression Driver',
              activeAssignmentCount: 1,
              assignmentEligible: false,
              eligibilityState: 'NOT_ELIGIBLE',
            }],
          },
        });
      }
      return null;
    },
  ]);
  try {
    await assert.rejects(
      () => cleanup.assertTestDriverEligibleForNewJob(
        'https://trider.taxi',
        'admin-token',
        '[E2E] Regression Driver',
      ),
      /active job/,
    );
  } finally {
    mock.restore();
  }
});

test('formatCleanupFailure prints structured cleanup error', () => {
  assert.equal(
    cleanup.formatCleanupFailure('TX202608150013', 'archive refused'),
    'CLEANUP_FAILED booking=TX202608150013 reason=archive refused',
  );
});

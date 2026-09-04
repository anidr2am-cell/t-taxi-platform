process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');

const app = require('../src/app');
const container = require('../src/helpers/container');
const MileageService = require('../src/services/mileage.service');
const MileageRepository = require('../src/repositories/mileage.repository');
const { formatServiceDateTimeForApi } = require('../src/utils/serviceDateTime.util');
const CustomerBookingService = require('../src/services/customerBooking.service');
const GuestBookingLookupService = require('../src/services/guestBookingLookup.service');

const USER_ID = 42;

function registerCustomerAuth(userId = USER_ID) {
  container.register('authService', () => ({
    verifyAccessToken() {
      return { id: userId, role: 'CUSTOMER', email: 'customer@test.local' };
    },
  }));
}

describe('MileageService.getTransactionHistoryForCustomer', () => {
  test('maps ledger rows with booking numbers and ISO dates', async () => {
    const mileageRepository = {
      async getTransactionHistoryWithBooking(userId, { page, limit }) {
        assert.equal(userId, 21);
        assert.equal(page, 1);
        assert.equal(limit, 10);
        return {
          items: [{
            created_at: '2026-07-01 09:30:00',
            amount: 80,
            type: 'ACCRUE',
            booking_number: 'TX202607010001',
          }],
          page: 1,
          limit: 10,
          total: 1,
        };
      },
    };
    const service = new MileageService({}, mileageRepository, {});

    const result = await service.getTransactionHistoryForCustomer(21, { page: 1, limit: 10 });

    assert.equal(result.total, 1);
    assert.equal(result.data.length, 1);
    assert.equal(result.data[0].amount, 80);
    assert.equal(result.data[0].type, 'ACCRUE');
    assert.equal(result.data[0].bookingNumber, 'TX202607010001');
    assert.equal(
      result.data[0].date,
      formatServiceDateTimeForApi('2026-07-01 09:30:00'),
    );
  });
});

describe('MileageRepository transaction history queries', () => {
  function normalizeSql(sql) {
    return sql.replace(/\s+/g, ' ').trim();
  }

  test('getTransactionHistoryWithBooking uses matching JOIN filter for COUNT and SELECT', async () => {
    const queries = [];
    const pool = {
      async query(sql, params) {
        queries.push({ sql: normalizeSql(sql), params });
        if (sql.includes('COUNT(*)')) {
          return [[{ total: 1 }]];
        }
        return [[{
          id: 10,
          user_id: 21,
          booking_id: 101,
          type: 'ACCRUE',
          amount: 80,
          balance_after: 80,
          created_at: '2026-07-01 09:30:00',
          booking_number: 'TX202607010001',
        }]];
      },
    };

    const repo = new MileageRepository(pool);
    const result = await repo.getTransactionHistoryWithBooking(21, { page: 1, limit: 20 });

    assert.equal(result.total, 1);
    assert.equal(result.items.length, 1);
    assert.equal(result.items[0].booking_number, 'TX202607010001');

    const countQuery = queries.find((entry) => entry.sql.includes('COUNT(*)'));
    const selectQuery = queries.find((entry) => entry.sql.includes('booking_number'));
    assert.ok(countQuery);
    assert.ok(selectQuery);
    assert.match(countQuery.sql, /INNER JOIN bookings b/);
    assert.match(countQuery.sql, /b\.deleted_at IS NULL/);
    assert.match(selectQuery.sql, /INNER JOIN bookings b/);
    assert.match(selectQuery.sql, /b\.deleted_at IS NULL/);
  });

  test('getTransactionHistoryWithBooking total excludes deleted-booking transactions', async () => {
    const pool = {
      async query(sql, params) {
        if (sql.includes('COUNT(*)')) {
          // Two mileage rows exist, but one booking is soft-deleted and filtered by JOIN.
          return [[{ total: 1 }]];
        }
        return [[{
          id: 11,
          user_id: 21,
          booking_id: 102,
          type: 'ACCRUE',
          amount: 120,
          balance_after: 120,
          created_at: '2026-07-02 10:00:00',
          booking_number: 'TX202607020002',
        }]];
      },
    };

    const repo = new MileageRepository(pool);
    const result = await repo.getTransactionHistoryWithBooking(21, { page: 1, limit: 20 });

    assert.equal(result.total, 1);
    assert.equal(result.items.length, 1);
    assert.equal(result.total, result.items.length);
  });

  test('getTransactionHistory keeps standalone mileage_transactions COUNT and rows', async () => {
    const pool = {
      async query(sql, params) {
        if (sql.includes('COUNT(*)')) {
          return [[{ total: 2 }]];
        }
        return [[
          {
            id: 1,
            user_id: 21,
            booking_id: 101,
            type: 'ACCRUE',
            amount: 80,
            balance_after: 80,
            created_at: '2026-07-01 09:30:00',
          },
          {
            id: 2,
            user_id: 21,
            booking_id: 999,
            type: 'ACCRUE',
            amount: 50,
            balance_after: 130,
            created_at: '2026-07-02 10:00:00',
          },
        ]];
      },
    };

    const repo = new MileageRepository(pool);
    const result = await repo.getTransactionHistory(21, { page: 1, limit: 20 });

    assert.equal(result.total, 2);
    assert.equal(result.items.length, 2);
    assert.equal(result.items[0].booking_number, undefined);
    assert.equal(result.total, result.items.length);
  });
});

describe('GET /api/v1/customer/mileage/transactions', () => {
  test('returns 401 without JWT', async () => {
    const res = await request(app).get('/api/v1/customer/mileage/transactions');
    assert.equal(res.status, 401);
  });

  test('returns paginated mileage transactions for authenticated customer', async () => {
    registerCustomerAuth(USER_ID);
    container.register('mileageService', () => ({
      async getTransactionHistoryForCustomer(userId, query) {
        assert.equal(userId, USER_ID);
        assert.equal(query.page, 2);
        assert.equal(query.limit, 5);
        return {
          data: [{
            date: '2026-07-01T09:30:00+07:00',
            amount: 80,
            type: 'ACCRUE',
            bookingNumber: 'TX202607010001',
          }],
          page: 2,
          limit: 5,
          total: 6,
        };
      },
    }));

    const res = await request(app)
      .get('/api/v1/customer/mileage/transactions?page=2&limit=5')
      .set('Authorization', 'Bearer customer-token')
      .expect(200);

    assert.equal(res.body.success, true);
    assert.equal(res.body.data.total, 6);
    assert.equal(res.body.data.page, 2);
    assert.equal(res.body.data.limit, 5);
    assert.equal(res.body.data.data.length, 1);
    assert.equal(res.body.data.data[0].bookingNumber, 'TX202607010001');
  });
});

describe('CustomerBookingService.getBookingStatusCounts', () => {
  test('returns grouped counts from repository', async () => {
    const bookingRepository = {
      async countStatusGroupsByCustomerUserId(userId) {
        assert.equal(userId, USER_ID);
        return {
          waiting: 2,
          assigned: 1,
          inProgress: 0,
          settlementPending: 1,
          completed: 3,
          reviewPending: 1,
        };
      },
    };
    const service = new CustomerBookingService(
      bookingRepository,
      new GuestBookingLookupService({}, bookingRepository, {}),
      null,
    );

    const counts = await service.getBookingStatusCounts(USER_ID);
    assert.deepEqual(counts, {
      waiting: 2,
      assigned: 1,
      inProgress: 0,
      settlementPending: 1,
      completed: 3,
      reviewPending: 1,
    });
  });
});

describe('GET /api/v1/customer/bookings/status-counts', () => {
  test('returns 401 without JWT', async () => {
    const res = await request(app).get('/api/v1/customer/bookings/status-counts');
    assert.equal(res.status, 401);
  });

  test('returns grouped booking counts for authenticated customer', async () => {
    registerCustomerAuth(USER_ID);
    container.register('customerBookingService', () => ({
      async getBookingStatusCounts(userId) {
        assert.equal(userId, USER_ID);
        return {
          waiting: 4,
          assigned: 2,
          inProgress: 1,
          settlementPending: 0,
          completed: 5,
          reviewPending: 2,
        };
      },
    }));

    const res = await request(app)
      .get('/api/v1/customer/bookings/status-counts')
      .set('Authorization', 'Bearer customer-token')
      .expect(200);

    assert.equal(res.body.success, true);
    assert.deepEqual(res.body.data, {
      waiting: 4,
      assigned: 2,
      inProgress: 1,
      settlementPending: 0,
      completed: 5,
      reviewPending: 2,
    });
  });
});

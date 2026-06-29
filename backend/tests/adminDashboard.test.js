process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const request = require('supertest');

const app = require('../src/app');
const container = require('../src/helpers/container');
const AdminDashboardService = require('../src/services/adminDashboard.service');
const AdminDashboardRepository = require('../src/repositories/adminDashboard.repository');

function sign(role = 'ADMIN', id = 1) {
  return jwt.sign(
    { sub: id, email: `${role.toLowerCase()}@example.com`, role, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

function metrics(overrides = {}) {
  return {
    date: '2026-06-29',
    timezone: 'Asia/Bangkok',
    bookings: {
      today: 2,
      pending: 1,
      unassigned: 1,
      assigned: 1,
      onRoute: 0,
      arrived: 0,
      completed: 0,
      cancelled: 0,
      noShow: 0,
    },
    drivers: { online: 1, activeJobs: 1 },
    settlements: { pending: 1, overdue: 0 },
    revenue: {
      currency: 'THB',
      todayBooked: 1200,
      todayCompleted: 900,
      byCurrency: [{ currency: 'THB', todayBooked: 1200, todayCompleted: 900 }],
    },
    updatedAt: '2026-06-29T05:00:00.000Z',
    ...overrides,
  };
}

test('ADMIN can read dashboard metrics', async () => {
  container.register('adminDashboardService', () => ({
    async getMetrics() {
      return metrics();
    },
  }));

  const res = await request(app)
    .get('/api/v1/admin/dashboard/metrics')
    .set('Authorization', `Bearer ${sign('ADMIN')}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.data.date, '2026-06-29');
  assert.equal(res.body.data.bookings.today, 2);
});

test('SUPER_ADMIN can read dashboard metrics', async () => {
  container.register('adminDashboardService', () => ({
    async getMetrics() {
      return metrics({ bookings: { ...metrics().bookings, today: 0 } });
    },
  }));

  const res = await request(app)
    .get('/api/v1/admin/dashboard/metrics')
    .set('Authorization', `Bearer ${sign('SUPER_ADMIN')}`);

  assert.equal(res.status, 200);
});

test('DRIVER and unauthenticated requests are rejected', async () => {
  const driver = await request(app)
    .get('/api/v1/admin/dashboard/metrics')
    .set('Authorization', `Bearer ${sign('DRIVER', 9)}`);
  assert.equal(driver.status, 403);

  const unauthenticated = await request(app).get('/api/v1/admin/dashboard/metrics');
  assert.equal(unauthenticated.status, 401);
});

test('service uses Thailand service-day boundaries near midnight', () => {
  const service = new AdminDashboardService({}, () => new Date('2026-06-28T17:00:00.000Z'));
  assert.deepEqual(service.serviceDayRange(), {
    date: '2026-06-29',
    start: '2026-06-29 00:00:00',
    end: '2026-06-30 00:00:00',
  });

  const late = new AdminDashboardService({}, () => new Date('2026-06-29T16:59:00.000Z'));
  assert.equal(late.serviceDayRange().date, '2026-06-29');
});

test('service maps status, driver, settlement, and revenue counts', async () => {
  const repository = {
    async getBookingMetrics() {
      return {
        today: '8',
        pending: '1',
        unassigned: '2',
        assigned: '1',
        on_route: '1',
        arrived: '1',
        completed: '1',
        cancelled: '1',
        no_show: '0',
      };
    },
    async getDriverMetrics() {
      return { online: '3', active_jobs: '2' };
    },
    async getSettlementMetrics() {
      return { pending: '4', overdue: '1' };
    },
    async getRevenueByCurrency() {
      return [{ currency: 'THB', today_booked: '1500.50', today_completed: '900.25' }];
    },
  };
  const service = new AdminDashboardService(repository, () => new Date('2026-06-29T05:00:00.000Z'));

  const result = await service.getMetrics();

  assert.equal(result.bookings.onRoute, 1);
  assert.equal(result.bookings.arrived, 1);
  assert.equal(result.drivers.online, 3);
  assert.equal(result.settlements.overdue, 1);
  assert.equal(result.revenue.currency, 'THB');
  assert.equal(result.revenue.todayBooked, 1500.50);
  assert.ok(!JSON.stringify(result).includes('customerPhone'));
});

test('empty database metrics return zeros', async () => {
  const repository = {
    async getBookingMetrics() { return {}; },
    async getDriverMetrics() { return {}; },
    async getSettlementMetrics() { return {}; },
    async getRevenueByCurrency() { return []; },
  };
  const service = new AdminDashboardService(repository, () => new Date('2026-06-29T05:00:00.000Z'));

  const result = await service.getMetrics();

  assert.equal(result.bookings.today, 0);
  assert.equal(result.drivers.online, 0);
  assert.equal(result.settlements.pending, 0);
  assert.equal(result.revenue.todayBooked, 0);
});

test('multiple revenue currencies are not combined', async () => {
  const repository = {
    async getBookingMetrics() { return {}; },
    async getDriverMetrics() { return {}; },
    async getSettlementMetrics() { return {}; },
    async getRevenueByCurrency() {
      return [
        { currency: 'THB', today_booked: '100', today_completed: '50' },
        { currency: 'USD', today_booked: '10', today_completed: '5' },
      ];
    },
  };
  const service = new AdminDashboardService(repository, () => new Date('2026-06-29T05:00:00.000Z'));

  const result = await service.getMetrics();

  assert.equal(result.revenue.currency, 'MULTIPLE');
  assert.equal(result.revenue.todayBooked, null);
  assert.equal(result.revenue.byCurrency.length, 2);
});

test('repository aggregate queries exclude soft-deleted rows and old assignments', async () => {
  const captured = [];
  const pool = {
    async query(sql, params) {
      captured.push({ sql, params });
      return [[{}]];
    },
  };
  const repository = new AdminDashboardRepository(pool);

  await repository.getBookingMetrics({
    start: '2026-06-29 00:00:00',
    end: '2026-06-30 00:00:00',
  });
  await repository.getDriverMetrics();
  await repository.getSettlementMetrics('2026-06-29 12:00:00');
  await repository.getRevenueByCurrency({
    start: '2026-06-29 00:00:00',
    end: '2026-06-30 00:00:00',
  });

  const allSql = captured.map((item) => item.sql).join('\n');
  assert.match(allSql, /b\.deleted_at IS NULL/);
  assert.match(allSql, /bda\.is_active = 1/);
  assert.match(allSql, /bda\.deleted_at IS NULL/);
  assert.match(allSql, /d\.deleted_at IS NULL/);
  assert.match(allSql, /GROUP BY currency/);
});

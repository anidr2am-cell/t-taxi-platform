process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const request = require('supertest');

const ERROR_CODES = require('../src/constants/errorCodes');
const container = require('../src/helpers/container');
const app = require('../src/app');

function sign(role, id) {
  return jwt.sign(
    { sub: id, email: `${role.toLowerCase()}@example.com`, role, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

function stubService(name, method, impl) {
  container.register(name, () => ({
    async [method](...args) {
      return impl(...args);
    },
  }));
}

test('DRIVER cannot access admin dispatch', async () => {
  const res = await request(app)
    .get('/api/v1/admin/bookings')
    .set('Authorization', `Bearer ${sign('DRIVER', 44)}`);
  assert.equal(res.status, 403);
  assert.equal(res.body.error_code, ERROR_CODES.FORBIDDEN);
});

test('CUSTOMER cannot access admin settlements', async () => {
  const res = await request(app)
    .get('/api/v1/admin/settlements')
    .set('Authorization', `Bearer ${sign('CUSTOMER', 8)}`);
  assert.equal(res.status, 403);
});

test('DRIVER cannot access admin chat queue', async () => {
  const res = await request(app)
    .get('/api/v1/admin/chats')
    .set('Authorization', `Bearer ${sign('DRIVER', 44)}`);
  assert.equal(res.status, 403);
});

test('ADMIN can access admin chat queue', async () => {
  stubService('chatService', 'listAdminChats', async () => ({ page: 1, pageSize: 20, total: 0, items: [] }));
  const res = await request(app)
    .get('/api/v1/admin/chats')
    .set('Authorization', `Bearer ${sign('ADMIN', 1)}`);
  assert.equal(res.status, 200);
});

test('unauthenticated request rejected for driver jobs', async () => {
  const res = await request(app).get('/api/v1/driver/bookings/today');
  assert.equal(res.status, 401);
});

test('public flight search does not require auth', async () => {
  container.register('flightService', () => ({
    async search() {
      return { items: [], provider: 'stub' };
    },
  }));
  const res = await request(app).get('/api/v1/public/flights/search?flightNumber=TG409&date=2026-07-01');
  assert.equal(res.status, 200);
});

test('deprecated chat route rejects without auth', async () => {
  const res = await request(app).post('/api/v1/chat/messages');
  assert.equal(res.status, 404);
});

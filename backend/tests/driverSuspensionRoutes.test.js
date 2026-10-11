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

function adminToken() {
  return jwt.sign(
    { sub: 7, email: 'admin@example.com', role: 'ADMIN', type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

test('admin suspension route contract matches the frontend paths', async () => {
  const calls = [];
  container.register('driverSuspensionService', () => ({
    async preview(id) { calls.push(['preview', id]); return { driverId: Number(id), canSuspend: true }; },
    async suspend(id, reason) { calls.push(['suspend', id, reason]); return { driverId: Number(id), status: 'SUSPENDED' }; },
    async unsuspend(id, reason) { calls.push(['unsuspend', id, reason]); return { driverId: Number(id), status: 'OFFLINE' }; },
    async history(id) { calls.push(['history', id]); return []; },
  }));
  const auth = `Bearer ${adminToken()}`;
  const preview = await request(app).get('/api/v1/admin/drivers/6/suspension-preview').set('Authorization', auth);
  const suspend = await request(app).post('/api/v1/admin/drivers/6/suspend').set('Authorization', auth).send({ reason: 'QA route contract' });
  const unsuspend = await request(app).post('/api/v1/admin/drivers/6/unsuspend').set('Authorization', auth).send({ reason: 'QA route contract' });
  const history = await request(app).get('/api/v1/admin/drivers/6/suspension-history').set('Authorization', auth);
  assert.equal(preview.status, 200);
  assert.equal(suspend.status, 200);
  assert.equal(unsuspend.status, 200);
  assert.equal(history.status, 200);
  assert.deepEqual(calls.map((row) => row[0]), ['preview', 'suspend', 'unsuspend', 'history']);
});

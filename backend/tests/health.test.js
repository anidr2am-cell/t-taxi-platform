const { test, afterEach } = require('node:test');
const assert = require('node:assert/strict');

process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const request = require('supertest');
const app = require('../src/app');
const database = require('../src/config/database');

const originalPing = database.ping;

afterEach(() => {
  database.ping = originalPing;
});

test('health returns non-sensitive process status', async () => {
  database.ping = async () => true;

  const response = await request(app).get('/api/v1/health').expect(200);

  assert.equal(response.body.success, true);
  assert.equal(response.body.data.status, 'ok');
  assert.equal(response.body.data.database, 'connected');
  assert.equal(JSON.stringify(response.body), JSON.stringify(response.body).replace(/secret|password|token/i, ''));
});

test('readiness reports database, upload, and optional integrations without secrets', async () => {
  database.ping = async () => true;

  const response = await request(app).get('/api/v1/health/readiness').expect(200);

  assert.equal(response.body.success, true);
  assert.equal(response.body.data.status, 'ready');
  assert.equal(response.body.data.checks.database, 'connected');
  assert.equal(response.body.data.checks.uploadDirectory, 'writable');
  assert.equal(typeof response.body.data.integrations.flightSyncEnabled, 'boolean');
  assert.equal(typeof response.body.data.integrations.aviationstackConfigured, 'boolean');

  const serialized = JSON.stringify(response.body).toLowerCase();
  assert.equal(serialized.includes('api_key'), false);
  assert.equal(serialized.includes('password'), false);
  assert.equal(serialized.includes('secret'), false);
});

test('readiness returns 503 when required database check fails', async () => {
  database.ping = async () => {
    throw new Error('db unavailable');
  };

  const response = await request(app).get('/api/v1/health/readiness').expect(503);

  assert.equal(response.body.success, true);
  assert.equal(response.body.data.status, 'degraded');
  assert.equal(response.body.data.checks.database, 'disconnected');
});

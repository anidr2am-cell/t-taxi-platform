const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');

process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';
process.env.CORS_ORIGIN = 'http://localhost:58001';

const {
  buildCorsPolicy,
  isLocalDevOrigin,
} = require('../src/config/cors');
const app = require('../src/app');
const container = require('../src/helpers/container');
const PlacesService = require('../src/services/places.service');

describe('CORS policy', () => {
  test('development allows arbitrary localhost port', () => {
    const policy = buildCorsPolicy({
      nodeEnv: 'development',
      corsOriginRaw: 'http://localhost:8080',
    });

    assert.equal(policy.isAllowedOrigin('http://localhost:1808'), true);
    assert.equal(policy.isAllowedOrigin('http://127.0.0.1:9999'), true);
    assert.equal(policy.isAllowedOrigin('http://localhost:8080'), true);
    assert.equal(policy.isAllowedOrigin('https://evil.example.com'), false);
  });

  test('staging rejects localhost ports not in allowlist', () => {
    const policy = buildCorsPolicy({
      nodeEnv: 'staging',
      corsOriginRaw: 'https://staging.example.com',
    });

    assert.equal(policy.isAllowedOrigin('http://localhost:1808'), false);
    assert.equal(policy.isAllowedOrigin('https://staging.example.com'), true);
  });

  test('allows requests without Origin header', () => {
    const policy = buildCorsPolicy({
      nodeEnv: 'staging',
      corsOriginRaw: 'https://staging.example.com',
    });

    assert.equal(policy.isAllowedOrigin(undefined), true);
    assert.equal(policy.isAllowedOrigin(''), true);
  });

  test('isLocalDevOrigin matches localhost and 127.0.0.1 with port', () => {
    assert.equal(isLocalDevOrigin('http://localhost:1808'), true);
    assert.equal(isLocalDevOrigin('http://127.0.0.1:3000'), true);
    assert.equal(isLocalDevOrigin('http://192.168.0.5:1808'), false);
  });
});

describe('CORS headers on Places routes', () => {
  test('autocomplete reflects allowed localhost origin', async () => {
    container.register('placesService', () => new PlacesService(
      { apiKey: 'test-key' },
      {
        async post() {
          return { data: { suggestions: [] } };
        },
      },
    ));

    const res = await request(app)
      .get('/api/v1/places/autocomplete')
      .query({ input: 'pattaya', language: 'en' })
      .set('Origin', 'http://localhost:1808');

    assert.equal(res.status, 200);
    assert.equal(res.headers['access-control-allow-origin'], 'http://localhost:1808');
    assert.equal(res.headers['access-control-allow-credentials'], 'true');
  });

  test('autocomplete OPTIONS preflight includes CORS headers', async () => {
    const res = await request(app)
      .options('/api/v1/places/autocomplete')
      .set('Origin', 'http://127.0.0.1:1808')
      .set('Access-Control-Request-Method', 'GET');

    assert.equal(res.status, 204);
    assert.equal(res.headers['access-control-allow-origin'], 'http://127.0.0.1:1808');
  });

  test('conditional GET can return 304 with CORS headers', async () => {
    container.register('placesService', () => new PlacesService(
      { apiKey: 'test-key' },
      {
        async post() {
          return { data: { suggestions: [] } };
        },
      },
    ));

    const first = await request(app)
      .get('/api/v1/places/autocomplete')
      .query({ input: 'pattaya', language: 'en' })
      .set('Origin', 'http://localhost:1808');

    assert.equal(first.status, 200);
    const etag = first.headers.etag;
    assert.ok(etag);

    const second = await request(app)
      .get('/api/v1/places/autocomplete')
      .query({ input: 'pattaya', language: 'en' })
      .set('Origin', 'http://localhost:1808')
      .set('If-None-Match', etag);

    assert.equal(second.status, 304);
    assert.equal(second.headers['access-control-allow-origin'], 'http://localhost:1808');
    assert.equal(second.headers['access-control-allow-credentials'], 'true');
  });
});

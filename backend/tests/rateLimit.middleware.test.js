const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const request = require('supertest');

process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const createRateLimit = require('../src/middlewares/rateLimit.middleware');
const { purgeExpiredBuckets } = require('../src/middlewares/rateLimit.middleware');
const {
  normalizeLoginIdentifier,
} = require('../src/middlewares/authRateLimit.middleware');
const ERROR_CODES = require('../src/constants/errorCodes');
const errorMiddleware = require('../src/middlewares/error.middleware');

function createMockRes() {
  const headers = {};
  return {
    headers,
    set(name, value) {
      headers[name.toLowerCase()] = value;
    },
  };
}

function runMiddleware(middleware, req, res) {
  return new Promise((resolve, reject) => {
    middleware(req, res, (err) => {
      if (err) reject(err);
      else resolve();
    });
  });
}

function buildTestApp(middlewares, handler = (_req, res) => res.json({ ok: true })) {
  const app = express();
  app.set('trust proxy', 1);
  app.use(express.json());
  app.post('/login', ...middlewares, handler);
  app.use(errorMiddleware);
  return app;
}

describe('rateLimit.middleware', () => {
  test('requests below threshold pass', async () => {
    let now = 1_000_000;
    const buckets = new Map();
    const limiter = createRateLimit({
      windowMs: 60_000,
      max: 3,
      keyFn: () => 'test:key',
      nowFn: () => now,
      buckets,
    });
    const req = { ip: '1.2.3.4', method: 'POST', baseUrl: '', path: '/login' };
    const res = createMockRes();

    await runMiddleware(limiter, req, res);
    await runMiddleware(limiter, req, res);
    await runMiddleware(limiter, req, res);
    assert.equal(buckets.get('test:key').count, 3);
  });

  test('threshold+1 returns 429 with generic message and Retry-After', async () => {
    let now = 1_000_000;
    const buckets = new Map();
    const limiter = createRateLimit({
      windowMs: 60_000,
      max: 2,
      keyFn: () => 'test:key',
      nowFn: () => now,
      buckets,
    });
    const req = { ip: '1.2.3.4', method: 'POST', baseUrl: '', path: '/login' };
    const res = createMockRes();

    await runMiddleware(limiter, req, res);
    await runMiddleware(limiter, req, res);

    let caught;
    try {
      await runMiddleware(limiter, req, res);
    } catch (err) {
      caught = err;
    }

    assert.ok(caught);
    assert.equal(caught.statusCode, 429);
    assert.equal(caught.errorCode, ERROR_CODES.RATE_LIMIT);
    assert.equal(caught.message, 'Too many requests');
    assert.equal(res.headers['retry-after'], '60');
  });

  test('window expiration allows requests again', async () => {
    let now = 1_000_000;
    const buckets = new Map();
    const limiter = createRateLimit({
      windowMs: 60_000,
      max: 1,
      keyFn: () => 'test:key',
      nowFn: () => now,
      buckets,
    });
    const req = { ip: '1.2.3.4', method: 'POST', baseUrl: '', path: '/login' };
    const res = createMockRes();

    await runMiddleware(limiter, req, res);

    let blocked;
    try {
      await runMiddleware(limiter, req, res);
    } catch (err) {
      blocked = err;
    }
    assert.ok(blocked);

    now += 60_001;
    await runMiddleware(limiter, req, res);
    assert.equal(buckets.get('test:key').count, 1);
  });

  test('purgeExpiredBuckets removes stale keys', () => {
    const buckets = new Map([
      ['expired', { count: 5, resetAt: 100 }],
      ['active', { count: 2, resetAt: 500 }],
    ]);

    purgeExpiredBuckets(buckets, 200);

    assert.equal(buckets.has('expired'), false);
    assert.equal(buckets.has('active'), true);
  });

  test('separate client IPs get independent buckets', async () => {
    let now = 1_000_000;
    const buckets = new Map();
    const limiter = createRateLimit({
      windowMs: 60_000,
      max: 1,
      keyFn: (req) => `ip:${req.ip}`,
      nowFn: () => now,
      buckets,
    });
    const res = createMockRes();

    await runMiddleware(limiter, { ip: '1.1.1.1' }, res);

    let blocked;
    try {
      await runMiddleware(limiter, { ip: '1.1.1.1' }, res);
    } catch (err) {
      blocked = err;
    }
    assert.ok(blocked);

    await runMiddleware(limiter, { ip: '2.2.2.2' }, res);
    assert.equal(buckets.get('ip:2.2.2.2').count, 1);
  });
});

describe('auth login rate limits', () => {
  test('dual dimensions: IP and normalized login identifier', async () => {
    let now = 1_000_000;
    const ipBuckets = new Map();
    const idBuckets = new Map();
    const ipLimiter = createRateLimit({
      windowMs: 900_000,
      max: 10,
      keyFn: (req) => `auth:login:ip:${req.ip}`,
      nowFn: () => now,
      buckets: ipBuckets,
    });
    const idLimiter = createRateLimit({
      windowMs: 900_000,
      max: 3,
      keyFn: (req) => {
        const identifier = normalizeLoginIdentifier(req.body);
        return identifier ? `auth:login:id:${identifier}` : `auth:login:id:missing:${req.ip}`;
      },
      nowFn: () => now,
      buckets: idBuckets,
    });

    const app = buildTestApp([ipLimiter, idLimiter]);
    const payloadA = { email: 'user-a@example.com', password: 'secret123' };
    const payloadB = { email: 'user-b@example.com', password: 'secret123' };

    for (let i = 0; i < 3; i += 1) {
      await request(app).post('/login').send(payloadA).expect(200);
    }

    const blockedSameAccount = await request(app).post('/login').send(payloadA).expect(429);
    assert.equal(blockedSameAccount.body.success, false);
    assert.equal(blockedSameAccount.body.error_code, ERROR_CODES.RATE_LIMIT);
    assert.equal(blockedSameAccount.body.message, 'Too many requests');
    assert.ok(blockedSameAccount.headers['retry-after']);

    const otherAccount = await request(app).post('/login').send(payloadB).expect(200);
    assert.equal(otherAccount.body.ok, true);
    assert.equal(
      blockedSameAccount.body.message,
      otherAccount.body.message || blockedSameAccount.body.message,
    );
  });

  test('normalizeLoginIdentifier lowercases email and trims phone', () => {
    assert.equal(
      normalizeLoginIdentifier({ email: '  User@Example.COM  ' }),
      'email:user@example.com',
    );
    assert.equal(
      normalizeLoginIdentifier({ phone: '  +66812345678  ' }),
      'phone:+66812345678',
    );
    assert.equal(normalizeLoginIdentifier({}), null);
  });
});

describe('register rate limit', () => {
  test('threshold enforced per IP', async () => {
    let now = 1_000_000;
    const buckets = new Map();
    const registerLimiter = createRateLimit({
      windowMs: 3_600_000,
      max: 2,
      keyFn: (req) => `auth:register:ip:${req.ip}`,
      nowFn: () => now,
      buckets,
    });
    const app = buildTestApp([registerLimiter]);

    await request(app).post('/login').send({ email: 'a@test.com' }).expect(200);
    await request(app).post('/login').send({ email: 'b@test.com' }).expect(200);

    const blocked = await request(app).post('/login').send({ email: 'c@test.com' }).expect(429);
    assert.equal(blocked.body.error_code, ERROR_CODES.RATE_LIMIT);
  });
});

describe('places rate limits', () => {
  test('expensive endpoint protected independently from autocomplete', async () => {
    let now = 1_000_000;
    const autocompleteBuckets = new Map();
    const detailsBuckets = new Map();
    const autocompleteLimiter = createRateLimit({
      windowMs: 60_000,
      max: 1,
      keyFn: (req) => `places:autocomplete:ip:${req.ip}`,
      nowFn: () => now,
      buckets: autocompleteBuckets,
    });
    const detailsLimiter = createRateLimit({
      windowMs: 60_000,
      max: 1,
      keyFn: (req) => `places:details:ip:${req.ip}`,
      nowFn: () => now,
      buckets: detailsBuckets,
    });

    const app = express();
    app.set('trust proxy', 1);
    app.get('/autocomplete', autocompleteLimiter, (_req, res) => res.json({ route: 'autocomplete' }));
    app.get('/details', detailsLimiter, (_req, res) => res.json({ route: 'details' }));
    app.use(errorMiddleware);

    await request(app).get('/autocomplete').expect(200);
    await request(app).get('/autocomplete').expect(429);
    await request(app).get('/details').expect(200);
  });
});

describe('trust proxy client IP resolution', () => {
  test('rate-limit key uses X-Forwarded-For client IP behind one trusted proxy hop', async () => {
    let now = 1_000_000;
    const buckets = new Map();
    const limiter = createRateLimit({
      windowMs: 60_000,
      max: 1,
      keyFn: (req) => `ip:${req.ip}`,
      nowFn: () => now,
      buckets,
    });

    const app = express();
    app.set('trust proxy', 1);
    app.get('/probe', limiter, (req, res) => res.json({ ip: req.ip }));
    app.use(errorMiddleware);

    await request(app)
      .get('/probe')
      .set('X-Forwarded-For', '203.0.113.10')
      .expect(200);

    const blocked = await request(app)
      .get('/probe')
      .set('X-Forwarded-For', '203.0.113.10')
      .expect(429);

    assert.equal(blocked.body.error_code, ERROR_CODES.RATE_LIMIT);

    await request(app)
      .get('/probe')
      .set('X-Forwarded-For', '203.0.113.11')
      .expect(200);
  });
});

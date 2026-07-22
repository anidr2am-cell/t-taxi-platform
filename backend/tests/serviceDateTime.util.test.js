process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');

const {
  formatServiceDateTimeForApi,
  parseServiceDateTimeToMs,
} = require('../src/utils/serviceDateTime.util');

test('formatServiceDateTimeForApi serializes mysql2 Date as naive Bangkok string', () => {
  const mysql2Date = new Date(Date.UTC(2026, 6, 23, 3, 24, 3, 24));

  assert.equal(
    formatServiceDateTimeForApi(mysql2Date),
    '2026-07-23 03:24:03',
  );
  assert.equal(
    parseServiceDateTimeToMs(formatServiceDateTimeForApi(mysql2Date)),
    parseServiceDateTimeToMs(mysql2Date),
  );
});

test('formatServiceDateTimeForApi normalizes ISO Z into naive Bangkok string', () => {
  assert.equal(
    formatServiceDateTimeForApi('2026-07-23T03:24:03.000Z'),
    '2026-07-23 03:24:03.000',
  );
});

test('formatServiceDateTimeForApi preserves existing naive MySQL strings', () => {
  assert.equal(
    formatServiceDateTimeForApi('2026-07-23 03:24:03.000'),
    '2026-07-23 03:24:03.000',
  );
});

test('formatServiceDateTimeForApi returns null for empty values', () => {
  assert.equal(formatServiceDateTimeForApi(null), null);
  assert.equal(formatServiceDateTimeForApi(''), null);
});

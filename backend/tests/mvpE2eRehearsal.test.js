process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  formatReport,
  stepResult,
  findLatestSeededBookings,
} = require('../scripts/mvpDemo/rehearsal');
const { parseArgs } = require('../scripts/mvp-e2e-rehearsal');
const { STATUS_SCENARIOS, customerPhoneForIndex } = require('../scripts/mvpDemo/fixtures');

test('formatReport summarizes pass and fail steps', () => {
  const report = {
    passed: false,
    total: 2,
    failedCount: 1,
    steps: [
      stepResult('create booking', true, 'TX202607040001'),
      stepResult('guest lookup', false, 'not found'),
    ],
  };
  const text = formatReport(report);
  assert.match(text, /PASS.*create booking/);
  assert.match(text, /FAIL.*guest lookup/);
  assert.match(text, /1 of 2 checks failed/);
});

test('parseArgs recognizes --service-only', () => {
  assert.equal(parseArgs(['--service-only']).serviceOnly, true);
  assert.equal(parseArgs([]).serviceOnly, false);
});

test('customerPhoneForIndex aligns with STATUS_SCENARIOS count', () => {
  assert.equal(STATUS_SCENARIOS.length, 6);
  assert.equal(customerPhoneForIndex(0), '+66820000001');
  assert.equal(customerPhoneForIndex(5), '+66820000006');
});

test('findLatestSeededBookings returns missing flags for empty pool stub', async () => {
  const pool = {
    async query() {
      return [[]];
    },
  };
  const rows = await findLatestSeededBookings(pool);
  assert.equal(rows.length, 6);
  assert.ok(rows.every((row) => row.missing === true));
});

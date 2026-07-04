process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createBookingSchema } = require('../src/validators/booking.validator');
const {
  STATUS_SCENARIOS,
  buildBookingPayload,
  customerPhoneForIndex,
  parseScenarioFilter,
  scheduledPickupAt,
} = require('../scripts/mvpDemo/fixtures');

test('buildBookingPayload passes booking validator', () => {
  const payload = buildBookingPayload({
    customerName: 'MVP Guest',
    customerPhone: '+66820000001',
    label: 'PENDING',
  });
  const { error } = createBookingSchema.validate(payload);
  assert.equal(error, undefined);
  assert.equal(payload.serviceTypeCode, 'AIRPORT_PICKUP');
  assert.equal(payload.originLocationCode, 'BKK');
  assert.equal(payload.destinationLocationCode, 'PATTAYA');
});

test('scheduledPickupAt is at least 2 hours ahead', () => {
  const value = scheduledPickupAt(3);
  const timestamp = Date.parse(value);
  assert.ok(timestamp >= Date.now() + 2 * 60 * 60 * 1000 - 1000);
});

test('customerPhoneForIndex returns distinct demo phones', () => {
  assert.equal(customerPhoneForIndex(0), '+66820000001');
  assert.equal(customerPhoneForIndex(5), '+66820000006');
});

test('parseScenarioFilter filters status scenarios', () => {
  const filtered = parseScenarioFilter('PENDING,COMPLETED');
  assert.equal(filtered.length, 2);
  assert.deepEqual(
    filtered.map((item) => item.status),
    ['PENDING', 'COMPLETED'],
  );
});

test('STATUS_SCENARIOS covers MVP manual E2E statuses', () => {
  const statuses = STATUS_SCENARIOS.map((item) => item.status);
  for (const status of [
    'PENDING',
    'DRIVER_ASSIGNED',
    'ON_ROUTE',
    'DRIVER_ARRIVED',
    'COMPLETED',
    'CANCELLED',
  ]) {
    assert.ok(statuses.includes(status), `missing ${status}`);
  }
});

test('seed-mvp-demo parseArgs recognizes skip flags', () => {
  const { parseArgs } = require('../scripts/seed-mvp-demo');
  const args = parseArgs(['--skip-admin', '--scenarios=PENDING']);
  assert.equal(args.skipAdmin, true);
  assert.equal(args.skipDriver, false);
  assert.equal(args.scenarios, 'PENDING');
});

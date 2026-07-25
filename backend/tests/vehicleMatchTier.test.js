const { test } = require('node:test');
const assert = require('node:assert/strict');

const {
  HIERARCHY_MATCH_TIERS_BY_CODE,
  EXACT_MATCH_ONLY_CODES,
  matchTierForCode,
  isBookingCompatibleWithDriverVehicles,
  isExactVehicleMatch,
  driverVehicleCoversBookingExistsSql,
  exactVehicleMatchExistsSql,
} = require('../src/utils/vehicleMatchTier');

const ALL_BOOKING_CODES = [
  'SEDAN',
  'SUV',
  'VAN',
  'VIP_SUV',
  'VIP_VAN',
  'LUXURY',
];

function visibleCodes(driverCodes) {
  return ALL_BOOKING_CODES.filter((code) =>
    isBookingCompatibleWithDriverVehicles(driverCodes, code));
}

test('hierarchy tier map is SEDAN < SUV < VAN only', () => {
  assert.equal(HIERARCHY_MATCH_TIERS_BY_CODE.SEDAN, 1);
  assert.equal(HIERARCHY_MATCH_TIERS_BY_CODE.SUV, 2);
  assert.equal(HIERARCHY_MATCH_TIERS_BY_CODE.VAN, 3);
  assert.equal(matchTierForCode('VIP_SUV'), null);
  assert.equal(matchTierForCode('VIP_VAN'), null);
  assert.equal(matchTierForCode('LUXURY'), null);
  assert.deepEqual(EXACT_MATCH_ONLY_CODES, ['VIP_SUV', 'VIP_VAN', 'LUXURY']);
});

test('SEDAN-only driver sees only SEDAN calls (regression — must not change)', () => {
  const visible = visibleCodes(['SEDAN']);
  assert.deepEqual(visible, ['SEDAN']);
  assert.equal(isExactVehicleMatch(['SEDAN'], 'SEDAN'), true);
  assert.equal(isBookingCompatibleWithDriverVehicles(['SEDAN'], 'SUV'), false);
  assert.equal(isBookingCompatibleWithDriverVehicles(['SEDAN'], 'VAN'), false);
  assert.equal(isBookingCompatibleWithDriverVehicles(['SEDAN'], 'VIP_SUV'), false);
  assert.equal(isBookingCompatibleWithDriverVehicles(['SEDAN'], 'LUXURY'), false);
});

test('VAN driver sees SEDAN/SUV/VAN and not VIP/LUXURY', () => {
  assert.deepEqual(visibleCodes(['VAN']), ['SEDAN', 'SUV', 'VAN']);
  assert.equal(isExactVehicleMatch(['VAN'], 'SEDAN'), false);
  assert.equal(isExactVehicleMatch(['VAN'], 'VAN'), true);
});

test('SUV driver sees SEDAN/SUV only — reverse VAN blocked', () => {
  assert.deepEqual(visibleCodes(['SUV']), ['SEDAN', 'SUV']);
  assert.equal(isBookingCompatibleWithDriverVehicles(['SUV'], 'VAN'), false);
});

test('SEDAN+VAN driver uses highest hierarchy tier (VAN) for full ladder', () => {
  assert.deepEqual(visibleCodes(['SEDAN', 'VAN']), ['SEDAN', 'SUV', 'VAN']);
  assert.equal(isExactVehicleMatch(['SEDAN', 'VAN'], 'SEDAN'), true);
  assert.equal(isExactVehicleMatch(['SEDAN', 'VAN'], 'SUV'), false);
  assert.equal(isExactVehicleMatch(['SEDAN', 'VAN'], 'VAN'), true);
});

test('VIP_SUV driver keeps exact-match-only behavior', () => {
  assert.deepEqual(visibleCodes(['VIP_SUV']), ['VIP_SUV']);
  assert.equal(isBookingCompatibleWithDriverVehicles(['VIP_SUV'], 'SUV'), false);
  assert.equal(isBookingCompatibleWithDriverVehicles(['VIP_SUV'], 'SEDAN'), false);
  assert.equal(isBookingCompatibleWithDriverVehicles(['VIP_SUV'], 'VAN'), false);
});

test('VIP_VAN and LUXURY stay exact-match-only', () => {
  assert.deepEqual(visibleCodes(['VIP_VAN']), ['VIP_VAN']);
  assert.deepEqual(visibleCodes(['LUXURY']), ['LUXURY']);
});

test('SQL fragments require approval_status and match_tier hierarchy (not sort_order)', () => {
  const covers = driverVehicleCoversBookingExistsSql();
  assert.match(covers, /approval_status/);
  assert.match(covers, /match_tier/);
  assert.doesNotMatch(covers, /sort_order/);
  assert.match(covers, /vt_driver\.match_tier >= vt_booking\.match_tier/);

  const exact = exactVehicleMatchExistsSql();
  assert.match(exact, /approval_status/);
  assert.match(exact, /vehicle_type_id =/);
});

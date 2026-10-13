process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const VehicleRecommendationService = require('../src/services/vehicleRecommendation.service');

// Production active type/rule snapshot, read on 2026-10-13 after migration 71.
const rules = [
  ['SEDAN', 1, 2, 2, 0, 0, 1],
  ['SUV', 2, 3, 2, 2, 1, 1],
  ['VIP_SUV', 3, 3, 2, 2, 1, 1],
  ['VAN', 4, 8, 8, 8, 4, 2],
].map(([code, sort_order, max_passengers, max_carriers_20_inch,
  max_carriers_24_inch_plus, max_golf_bags, max_special_luggage]) => ({
  code, sort_order, max_passengers, max_carriers_20_inch,
  max_carriers_24_inch_plus, max_golf_bags, max_special_luggage,
}));

function service(includeVipSuv) {
  const active = rules.filter((row) => includeVipSuv || row.code !== 'VIP_SUV');
  return new VehicleRecommendationService({
    async findActiveTypesOrdered() { return active; },
    async findActiveCapacityRules() { return active; },
  });
}

test('VIP_SUV deactivation preserves recommendations across the full active capacity domain', async () => {
  const before = service(true);
  const after = service(false);
  const summary = {};
  let count = 0;
  let formerVipCapacityCount = 0;
  for (let adults = 1; adults <= 8; adults += 1) {
    for (let luggage20 = 0; luggage20 <= 8; luggage20 += 1) {
      for (let luggage24 = 0; luggage24 <= 8; luggage24 += 1) {
        for (let golfBags = 0; golfBags <= 4; golfBags += 1) {
          for (let specialLuggageCount = 0; specialLuggageCount <= 2; specialLuggageCount += 1) {
            const input = { adults, luggage20, luggage24, golfBags, specialLuggageCount };
            const previous = await before.recommend(input);
            const next = await after.recommend(input);
            assert.equal(next.recommendedVehicle, previous.recommendedVehicle, JSON.stringify(input));
            assert.equal(next.multipleVehicles, previous.multipleVehicles, JSON.stringify(input));
            assert.ok(next.recommendedVehicle);
            assert.equal(next.multipleVehicles, false);
            assert.deepEqual(next.selectableVehicles,
              previous.selectableVehicles.filter((code) => code !== 'VIP_SUV'));
            count += 1;
            if (adults <= 3 && luggage20 <= 2 && luggage24 <= 2 && golfBags <= 1 && specialLuggageCount <= 1) {
              formerVipCapacityCount += 1;
              const key = `${previous.recommendedVehicle}->${next.recommendedVehicle}`;
              summary[key] = (summary[key] || 0) + 1;
            }
          }
        }
      }
    }
  }
  assert.equal(count, 9720);
  assert.equal(formerVipCapacityCount, 108);
  console.log(JSON.stringify({ count, formerVipCapacityCount, summary, unavailable: 0 }));
});

test('migration 72 and rollback change only is_active on the exact VIP_SUV rows', () => {
  for (const [file, value] of [
    ['72_deactivate_vip_suv.sql', 0],
    ['rollback/72_deactivate_vip_suv.rollback.sql', 1],
  ]) {
    const sql = fs.readFileSync(path.join(__dirname, '../../database', file), 'utf8');
    assert.match(sql, /START TRANSACTION;/);
    assert.match(sql, /COMMIT;/);
    assert.match(sql, /vcr\.id = 3/);
    assert.match(sql, /vt\.id = 3/);
    assert.match(sql, /code = 'VIP_SUV'/);
    assert.match(sql, new RegExp(`SET (?:vcr\\.)?is_active = ${value}`));
    assert.doesNotMatch(sql, /\b(?:DELETE|DROP|ALTER|INSERT)\b/i);
    const assignments = [...sql.matchAll(/SET\s+(?:vcr\.)?(\w+)\s*=/g)].map((match) => match[1]);
    assert.deepEqual(assignments, ['is_active', 'is_active']);
  }
});

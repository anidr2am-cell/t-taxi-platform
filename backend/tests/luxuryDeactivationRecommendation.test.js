process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const VehicleRecommendationService = require('../src/services/vehicleRecommendation.service');

const vehicleTypes = [
  { code: 'SEDAN', sort_order: 1 },
  { code: 'SUV', sort_order: 2 },
  { code: 'VIP_SUV', sort_order: 3 },
  { code: 'VAN', sort_order: 4 },
  { code: 'VIP_VAN', sort_order: 5 },
  { code: 'LUXURY', sort_order: 6 },
];
const rules = [
  { code: 'SEDAN', sort_order: 1, max_passengers: 2, max_carriers_20_inch: 2, max_carriers_24_inch_plus: 0, max_golf_bags: 0, max_special_luggage: 1 },
  { code: 'SUV', sort_order: 2, max_passengers: 3, max_carriers_20_inch: 2, max_carriers_24_inch_plus: 2, max_golf_bags: 1, max_special_luggage: 1 },
  { code: 'VIP_SUV', sort_order: 3, max_passengers: 3, max_carriers_20_inch: 2, max_carriers_24_inch_plus: 2, max_golf_bags: 1, max_special_luggage: 1 },
  { code: 'VAN', sort_order: 4, max_passengers: 8, max_carriers_20_inch: 8, max_carriers_24_inch_plus: 8, max_golf_bags: 4, max_special_luggage: 2 },
  { code: 'VIP_VAN', sort_order: 5, max_passengers: 6, max_carriers_20_inch: 6, max_carriers_24_inch_plus: 6, max_golf_bags: 3, max_special_luggage: 2 },
  { code: 'LUXURY', sort_order: 6, max_passengers: 3, max_carriers_20_inch: 2, max_carriers_24_inch_plus: 2, max_golf_bags: 1, max_special_luggage: 1 },
];

function service(includeLuxury) {
  return new VehicleRecommendationService({
    async findActiveTypesOrdered() {
      return vehicleTypes.filter((row) => includeLuxury || row.code !== 'LUXURY');
    },
    async findActiveCapacityRules() {
      return rules.filter((row) => includeLuxury || row.code !== 'LUXURY');
    },
  });
}

test('disabling LUXURY preserves recommendations for every combination within its capacity', async () => {
  const before = service(true);
  const after = service(false);
  const unavailable = [];

  for (let adults = 1; adults <= 3; adults += 1) {
    for (let luggage20 = 0; luggage20 <= 2; luggage20 += 1) {
      for (let luggage24 = 0; luggage24 <= 2; luggage24 += 1) {
        for (let golfBags = 0; golfBags <= 1; golfBags += 1) {
          for (let specialLuggageCount = 0; specialLuggageCount <= 1; specialLuggageCount += 1) {
            const input = {
              adults,
              children: 0,
              infants: 0,
              luggage20,
              luggage24,
              golfBags,
              specialLuggageCount,
            };
            const beforeResult = await before.recommend(input);
            const afterResult = await after.recommend(input);
            if (afterResult.multipleVehicles || afterResult.recommendedVehicle == null) {
              unavailable.push(input);
            }
            assert.equal(afterResult.recommendedVehicle, beforeResult.recommendedVehicle);
            assert.equal(afterResult.multipleVehicles, beforeResult.multipleVehicles);
          }
        }
      }
    }
  }

  assert.deepEqual(unavailable, []);
});

test('the former maximum LUXURY combination remains covered by SUV', async () => {
  const result = await service(false).recommend({
    adults: 3,
    luggage20: 2,
    luggage24: 2,
    golfBags: 1,
    specialLuggageCount: 0,
  });
  assert.equal(result.multipleVehicles, false);
  assert.equal(result.recommendedVehicle, 'SUV');
  assert.deepEqual(result.selectableVehicles, ['SUV', 'VIP_SUV', 'VAN', 'VIP_VAN']);
});

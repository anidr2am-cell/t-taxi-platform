process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const PricingService = require('../src/services/pricing.service');
const { estimateRoadDistanceKm } = require('../src/utils/geo.util');

// Place coordinates were resolved through the production Google Places proxy
// on 2026-10-13. Registered route anchors come from migration 66.
const points = {
  BKK: [13.689999, 100.747924],
  DMK: [13.91326, 100.60201],
  PATTAYA: [12.9236, 100.8825],
  BANGKOK: [13.7563, 100.5018],
  RAYONG: [12.6814, 101.2816],
  SN: [12.9477908, 100.8968352],
  JOMTIEN: [12.8911658, 100.8736814],
  NAKLUA: [12.9523743, 100.8847986],
  J_PARK: [13.1542112, 100.9836189],
  BANGSAEN: [13.2751426, 100.9288993],
  RAYONG_CITY: [12.6813957, 101.2816261],
  SUKHUMVIT: [13.7155852, 100.5905761],
  SILOM: [13.7237445, 100.5295569],
  KHAO_SAN: [13.7581072, 100.4989781],
  DON_MUEANG: [13.9272289, 100.5858593],
  BANG_NA: [13.663853, 100.6132453],
};

const serviceTypes = [
  { id: 1, code: 'AIRPORT_PICKUP' },
  { id: 2, code: 'AIRPORT_DROPOFF' },
  { id: 3, code: 'CITY_TRANSFER' },
];
const locations = [
  { id: 1, code: 'BKK', latitude: points.BKK[0], longitude: points.BKK[1] },
  { id: 2, code: 'DMK', latitude: points.DMK[0], longitude: points.DMK[1] },
  { id: 3, code: 'PATTAYA', latitude: points.PATTAYA[0], longitude: points.PATTAYA[1] },
  { id: 4, code: 'BANGKOK', latitude: points.BANGKOK[0], longitude: points.BANGKOK[1] },
  { id: 5, code: 'RAYONG', latitude: points.RAYONG[0], longitude: points.RAYONG[1] },
];
const vehicleTypes = [
  { id: 1, code: 'SEDAN' },
  { id: 2, code: 'SUV' },
  { id: 3, code: 'VAN' },
];

function makeRoute(id, serviceTypeId, originCode, destinationCode, prices) {
  const origin = locations.find((row) => row.code === originCode);
  const destination = locations.find((row) => row.code === destinationCode);
  return {
    id,
    serviceTypeId,
    originLocationId: origin.id,
    originLocationCode: origin.code,
    originLatitude: origin.latitude,
    originLongitude: origin.longitude,
    destinationLocationId: destination.id,
    destinationLocationCode: destination.code,
    destinationLatitude: destination.latitude,
    destinationLongitude: destination.longitude,
    prices,
    isActive: true,
    effectiveFrom: null,
    effectiveTo: null,
  };
}

const routes = [
  makeRoute(1, 1, 'BKK', 'PATTAYA', [1000, 1300, 1700]),
  makeRoute(2, 1, 'BKK', 'BANGKOK', [550, 600, 1100]),
  makeRoute(3, 1, 'BKK', 'RAYONG', [1500, 1700, 2100]),
  makeRoute(4, 1, 'DMK', 'PATTAYA', [1400, 1600, 2200]),
  makeRoute(5, 1, 'DMK', 'BANGKOK', [600, 800, 1200]),
  makeRoute(6, 2, 'PATTAYA', 'BKK', [1000, 1300, 1700]),
  makeRoute(7, 2, 'BANGKOK', 'BKK', [700, 800, 1200]),
  makeRoute(8, 3, 'BANGKOK', 'PATTAYA', [1300, 1600, 2000]),
  makeRoute(9, 3, 'PATTAYA', 'BANGKOK', [1300, 1500, 2000]),
];

const scenarios = [
  ['BKK pickup / Pattaya center', 'AIRPORT_PICKUP', 'BKK', 'PATTAYA', 1, [1000, 1300, 1700], [1000, 1300, 1700]],
  ['BKK pickup / SN Plus', 'AIRPORT_PICKUP', 'BKK', 'SN', 1, [1000, 1300, 1700], [1000, 1300, 1700]],
  ['BKK pickup / Jomtien', 'AIRPORT_PICKUP', 'BKK', 'JOMTIEN', 1, [1000, 1300, 1700], [1000, 1300, 1700]],
  ['BKK pickup / Naklua', 'AIRPORT_PICKUP', 'BKK', 'NAKLUA', 1, [1000, 1300, 1700], [1000, 1300, 1700]],
  ['BKK pickup / J Park', 'AIRPORT_PICKUP', 'BKK', 'J_PARK', 1, [1300, 1600, 2000], [1000, 1300, 1700]],
  ['BKK pickup / Bangsaen', 'AIRPORT_PICKUP', 'BKK', 'BANGSAEN', 1, [1500, 1800, 2200], [1000, 1300, 1700]],
  ['BKK pickup / Rayong', 'AIRPORT_PICKUP', 'BKK', 'RAYONG_CITY', 3, [1500, 1700, 2100], [1500, 1700, 2100]],
  ['BKK pickup / Sukhumvit', 'AIRPORT_PICKUP', 'BKK', 'SUKHUMVIT', 2, [650, 700, 1200], [550, 600, 1100]],
  ['BKK pickup / Silom', 'AIRPORT_PICKUP', 'BKK', 'SILOM', 2, [550, 600, 1100], [550, 600, 1100]],
  ['BKK pickup / Khao San', 'AIRPORT_PICKUP', 'BKK', 'KHAO_SAN', 2, [550, 600, 1100], [550, 600, 1100]],
  ['BKK pickup / Don Mueang area', 'AIRPORT_PICKUP', 'BKK', 'DON_MUEANG', 2, [750, 800, 1300], [550, 600, 1100]],
  ['BKK pickup / Bang Na', 'AIRPORT_PICKUP', 'BKK', 'BANG_NA', 2, [750, 800, 1300], [550, 600, 1100]],
  ['DMK pickup / Pattaya center', 'AIRPORT_PICKUP', 'DMK', 'PATTAYA', 4, [1400, 1600, 2200], [1400, 1600, 2200]],
  ['DMK pickup / Sukhumvit', 'AIRPORT_PICKUP', 'DMK', 'SUKHUMVIT', 5, [700, 900, 1300], [600, 800, 1200]],
  ['DMK pickup / Silom', 'AIRPORT_PICKUP', 'DMK', 'SILOM', 5, [600, 800, 1200], [600, 800, 1200]],
  ['Dropoff SN Plus / BKK', 'AIRPORT_DROPOFF', 'SN', 'BKK', 6, [1000, 1300, 1700], [1000, 1300, 1700]],
  ['Dropoff J Park / BKK', 'AIRPORT_DROPOFF', 'J_PARK', 'BKK', 6, [1300, 1600, 2000], [1000, 1300, 1700]],
  ['Dropoff Sukhumvit / BKK', 'AIRPORT_DROPOFF', 'SUKHUMVIT', 'BKK', 7, [800, 900, 1300], [700, 800, 1200]],
  ['City Sukhumvit / Pattaya', 'CITY_TRANSFER', 'SUKHUMVIT', 'PATTAYA', 8, [1400, 1700, 2100], [1300, 1600, 2000]],
  ['City Pattaya / Silom', 'CITY_TRANSFER', 'PATTAYA', 'SILOM', 9, [1300, 1500, 2000], [1300, 1500, 2000]],
];

function makeService() {
  return new PricingService(
    { async findByCode(code) { return serviceTypes.find((row) => row.code === code) ?? null; } },
    {
      async findById(id) { return locations.find((row) => row.id === Number(id)) ?? null; },
      async findByCode(code) { return locations.find((row) => row.code === code) ?? null; },
      async findByAirportIata(code) { return locations.find((row) => row.code === code) ?? null; },
    },
    {
      async findActiveByServiceAndLocations(serviceTypeId, originId, destinationId) {
        return routes.filter((route) => route.serviceTypeId === serviceTypeId
          && route.originLocationId === originId && route.destinationLocationId === destinationId);
      },
      async findActiveByService(serviceTypeId) {
        return routes.filter((route) => route.serviceTypeId === serviceTypeId);
      },
    },
    {
      async findByRouteId(routeId) {
        const route = routes.find((row) => row.id === routeId);
        return vehicleTypes.map((vehicle, index) => ({
          id: routeId * 10 + vehicle.id,
          routeId,
          vehicleTypeId: vehicle.id,
          price: route.prices[index],
          currency: 'THB',
          isActive: true,
          effectiveFrom: null,
          effectiveTo: null,
        }));
      },
    },
    { async findActivePolicies() { return []; } },
    { async findTypeByCode(code) { return vehicleTypes.find((row) => row.code === code) ?? null; } },
  );
}

function legacySteps(distanceKm) {
  return distanceKm <= 10 ? 0 : Math.ceil((distanceKm - 10) / 10);
}

function legacyTotal(route, origin, destination, base) {
  const originDeviation = estimateRoadDistanceKm(
    points[origin][0], points[origin][1], route.originLatitude, route.originLongitude,
  );
  const destinationDeviation = estimateRoadDistanceKm(
    points[destination][0], points[destination][1],
    route.destinationLatitude, route.destinationLongitude,
  );
  return base + (legacySteps(originDeviation) + legacySteps(destinationDeviation)) * 100;
}

test('all approved C-option scenarios match the before/after fare matrix for sedan, SUV and van', async () => {
  for (const [name, serviceCode, originKey, destinationKey, routeId, before, after] of scenarios) {
    const route = routes.find((row) => row.id === routeId);
    for (let index = 0; index < vehicleTypes.length; index += 1) {
      assert.equal(
        legacyTotal(route, originKey, destinationKey, route.prices[index]),
        before[index],
        `${name} ${vehicleTypes[index].code} legacy fare`,
      );
      const result = await makeService().calculate({
        serviceTypeCode: serviceCode,
        vehicleTypeCode: vehicleTypes[index].code,
        originLocationCode: route.originLocationCode,
        destinationLocationCode: route.destinationLocationCode,
        originLat: points[originKey][0],
        originLng: points[originKey][1],
        destinationLat: points[destinationKey][0],
        destinationLng: points[destinationKey][1],
      });
      assert.equal(result.routeId, routeId, `${name} selected route`);
      assert.equal(result.totalAmount, after[index], `${name} ${vehicleTypes[index].code} C-option fare`);
    }
  }
});

process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const PricingService = require('../src/services/pricing.service');
const CHARGE_TYPES = require('../src/constants/chargeTypes');

const locations = [
  { id: 1, code: 'BKK', latitude: 13.69, longitude: 100.75 },
  { id: 2, code: 'PATTAYA', latitude: 12.9236, longitude: 100.8825 },
  { id: 3, code: 'BANGKOK', latitude: 13.7563, longitude: 100.5018 },
];
const serviceTypes = [
  { id: 1, code: 'AIRPORT_PICKUP' },
  { id: 2, code: 'AIRPORT_DROPOFF' },
  { id: 3, code: 'CITY_TRANSFER' },
];

function route(id, serviceTypeId, origin, destination) {
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
    isActive: true,
    effectiveFrom: null,
    effectiveTo: null,
  };
}

const routes = [
  route(10, 1, locations[0], locations[1]),
  route(20, 2, locations[1], locations[0]),
  route(30, 3, locations[2], locations[1]),
];

function makeService() {
  return new PricingService(
    {
      async findByCode(code) { return serviceTypes.find((row) => row.code === code) ?? null; },
    },
    {
      async findById(id) { return locations.find((row) => row.id === Number(id)) ?? null; },
      async findByCode(code) { return locations.find((row) => row.code === code) ?? null; },
      async findByAirportIata(code) { return locations.find((row) => row.code === code) ?? null; },
    },
    {
      async findActiveByServiceAndLocations(serviceTypeId, originId, destinationId) {
        return routes.filter((item) => item.serviceTypeId === serviceTypeId
          && item.originLocationId === originId
          && item.destinationLocationId === destinationId);
      },
      async findActiveByService(serviceTypeId) {
        return routes.filter((item) => item.serviceTypeId === serviceTypeId);
      },
    },
    {
      async findByRouteId(routeId) {
        return [{
          id: routeId * 10,
          routeId,
          vehicleTypeId: 1,
          price: routeId === 30 ? 1300 : 1000,
          currency: 'THB',
          isActive: true,
          effectiveFrom: null,
          effectiveTo: null,
        }];
      },
    },
    { async findActivePolicies() { return []; } },
    { async findTypeByCode() { return { id: 1, code: 'SEDAN' }; } },
  );
}

function distanceCharge(result) {
  return result.chargeItems.find((item) => item.chargeType === CHARGE_TYPES.DISTANCE_SURCHARGE);
}

test('distance steps include 10 km and add 100 THB for every started 10 km beyond it', () => {
  const service = makeService();
  assert.equal(service.distanceSteps(10), 0);
  assert.equal(service.distanceSteps(10.01), 1);
  assert.equal(service.distanceSteps(20), 1);
  assert.equal(service.distanceSteps(20.01), 2);
});

test('airport pickup keeps the configured fare inside the destination 10 km area', async () => {
  const result = await makeService().calculate({
    serviceTypeCode: 'AIRPORT_PICKUP',
    vehicleTypeCode: 'SEDAN',
    originAirportIata: 'BKK',
    destinationRegion: 'Hotel near Pattaya',
    originLat: 13.69,
    originLng: 100.75,
    destinationLat: 12.96,
    destinationLng: 100.8825,
  });
  assert.equal(result.totalAmount, 1000);
  assert.equal(distanceCharge(result), undefined);
  assert.equal(result.routeId, 10);
});

test('airport pickup adds 100 THB per 10 km step outside the included area', async () => {
  const result = await makeService().calculate({
    serviceTypeCode: 'AIRPORT_PICKUP',
    vehicleTypeCode: 'SEDAN',
    originAirportIata: 'BKK',
    destinationRegion: 'Hotel outside Pattaya',
    originLat: 13.69,
    originLng: 100.75,
    destinationLat: 13.08,
    destinationLng: 100.8825,
  });
  assert.equal(result.totalAmount, 1200);
  assert.equal(distanceCharge(result).amount, 200);
  assert.equal(result.routeId, 10);
});

test('airport dropoff uses the nearest configured route and measures the custom origin', async () => {
  const result = await makeService().calculate({
    serviceTypeCode: 'AIRPORT_DROPOFF',
    vehicleTypeCode: 'SEDAN',
    originLocationCode: 'Unknown Pattaya hotel',
    destinationLocationCode: 'BKK',
    originLat: 13.08,
    originLng: 100.8825,
    destinationLat: 13.69,
    destinationLng: 100.75,
  });
  assert.equal(result.totalAmount, 1200);
  assert.equal(distanceCharge(result).amount, 200);
  assert.equal(result.routeId, 20);
});

test('city transfer gives each endpoint its own included 10 km area', async () => {
  const result = await makeService().calculate({
    serviceTypeCode: 'CITY_TRANSFER',
    vehicleTypeCode: 'SEDAN',
    originLocationCode: 'Unknown Bangkok hotel',
    destinationRegion: 'Unknown Pattaya hotel',
    originLat: 13.87,
    originLng: 100.5018,
    destinationLat: 13.04,
    destinationLng: 100.8825,
  });
  assert.equal(result.totalAmount, 1500);
  assert.equal(distanceCharge(result).amount, 200);
  assert.equal(result.routeId, 30);
});

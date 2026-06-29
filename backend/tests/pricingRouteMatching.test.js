process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const PricingService = require('../src/services/pricing.service');
const ERROR_CODES = require('../src/constants/errorCodes');

function makePricingService(overrides = {}) {
  const serviceTypes = [
    { id: 1, code: 'AIRPORT_PICKUP' },
    { id: 2, code: 'AIRPORT_DROPOFF' },
  ];
  const locations = [
    { id: 1, code: 'BKK', type: 'AIRPORT', is_active: 1 },
    { id: 8, code: 'PATTAYA', type: 'CITY', is_active: 1 },
    { id: 9, code: 'BANGKOK', type: 'CITY', is_active: 1 },
  ];
  const routes = overrides.routes ?? [
    {
      id: 1,
      serviceTypeId: 1,
      serviceTypeCode: 'AIRPORT_PICKUP',
      originLocationId: 1,
      destinationLocationId: 8,
      isActive: true,
      effectiveFrom: null,
      effectiveTo: null,
    },
  ];
  const prices = overrides.prices ?? [
    {
      id: 1,
      routeId: 1,
      vehicleTypeId: 1,
      price: 800,
      currency: 'THB',
      isActive: true,
      effectiveFrom: null,
      effectiveTo: null,
    },
  ];

  return new PricingService(
    {
      async findByCode(code) {
        return serviceTypes.find((row) => row.code === code) ?? null;
      },
      async findById(id) {
        return serviceTypes.find((row) => row.id === id) ?? null;
      },
    },
    {
      async findById(id) {
        return locations.find((row) => row.id === Number(id)) ?? null;
      },
      async findByCode(code) {
        return locations.find((row) => row.code === code) ?? null;
      },
      async findByAirportIata(iata) {
        return iata === 'BKK' ? locations[0] : null;
      },
    },
    {
      async findActiveByServiceAndLocations(serviceTypeId, originLocationId, destinationLocationId) {
        return routes.filter((route) => route.serviceTypeId === serviceTypeId
          && route.originLocationId === originLocationId
          && route.destinationLocationId === destinationLocationId
          && route.isActive
          && !route.deletedAt);
      },
    },
    {
      async findByRouteId(routeId) {
        return prices.filter((price) => price.routeId === routeId && !price.deletedAt);
      },
    },
    {
      async findActivePolicies() {
        return [];
      },
    },
    {
      async findTypeByCode(code) {
        return code === 'SEDAN' ? { id: 1, code: 'SEDAN' } : null;
      },
    },
  );
}

test('BKK to Pattaya airport pickup route resolves with configured IDs', async () => {
  const result = await makePricingService().calculate({
    serviceTypeCode: 'AIRPORT_PICKUP',
    vehicleTypeCode: 'SEDAN',
    originAirportIata: 'BKK',
    destinationLocationCode: 'PATTAYA',
  });

  assert.equal(result.routeId, 1);
  assert.equal(result.vehiclePriceId, 1);
  assert.equal(result.totalAmount, 800);
});

test('Pattaya Google region aliases normalize to configured internal location code', async () => {
  const result = await makePricingService().calculate({
    serviceTypeCode: 'AIRPORT_PICKUP',
    vehicleTypeCode: 'SEDAN',
    originAirportIata: 'BKK',
    destinationRegion: 'เมืองพัทยา Chon Buri Thailand',
  });

  assert.equal(result.routeId, 1);
});

test('reversed route does not resolve unless separately configured', async () => {
  await assert.rejects(
    () => makePricingService().calculate({
      serviceTypeCode: 'AIRPORT_PICKUP',
      vehicleTypeCode: 'SEDAN',
      originLocationCode: 'PATTAYA',
      destinationLocationCode: 'BKK',
    }),
    (err) => err.errorCode === ERROR_CODES.NOT_FOUND
      && /Route not found/.test(err.message),
  );
});

test('unknown destination still returns controlled not found', async () => {
  await assert.rejects(
    () => makePricingService().calculate({
      serviceTypeCode: 'AIRPORT_PICKUP',
      vehicleTypeCode: 'SEDAN',
      originAirportIata: 'BKK',
      destinationRegion: 'Unknown Resort Area',
    }),
    (err) => err.errorCode === ERROR_CODES.NOT_FOUND,
  );
});

test('inactive or deleted route is excluded from route matching', async () => {
  await assert.rejects(
    () => makePricingService({
      routes: [{
        id: 1,
        serviceTypeId: 1,
        serviceTypeCode: 'AIRPORT_PICKUP',
        originLocationId: 1,
        destinationLocationId: 8,
        isActive: false,
      }],
    }).calculate({
      serviceTypeCode: 'AIRPORT_PICKUP',
      vehicleTypeCode: 'SEDAN',
      originAirportIata: 'BKK',
      destinationLocationCode: 'PATTAYA',
    }),
    (err) => err.errorCode === ERROR_CODES.NOT_FOUND
      && /Route not found/.test(err.message),
  );
});

test('missing vehicle price returns distinct vehicle price error', async () => {
  await assert.rejects(
    () => makePricingService({ prices: [] }).calculate({
      serviceTypeCode: 'AIRPORT_PICKUP',
      vehicleTypeCode: 'SEDAN',
      originAirportIata: 'BKK',
      destinationLocationCode: 'PATTAYA',
    }),
    (err) => err.errorCode === ERROR_CODES.NOT_FOUND
      && /Vehicle price not configured/.test(err.message),
  );
});

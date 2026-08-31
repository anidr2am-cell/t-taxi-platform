process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const PricingService = require('../src/services/pricing.service');
const CityTransferDistancePricingService = require('../src/services/cityTransferDistancePricing.service');
const ERROR_CODES = require('../src/constants/errorCodes');
const { estimateRoadDistanceKm } = require('../src/utils/geo.util');

const DISTANCE_BANDS = [
  {
    id: 1,
    minKm: 0,
    maxKm: 12,
    sedanPrice: null,
    suvPrice: null,
    vanPrice: null,
    currency: 'THB',
    isActive: true,
  },
  {
    id: 2,
    minKm: 13,
    maxKm: 50,
    sedanPrice: 900,
    suvPrice: 1100,
    vanPrice: 1400,
    currency: 'THB',
    isActive: true,
  },
  {
    id: 3,
    minKm: 51,
    maxKm: 100,
    sedanPrice: 1100,
    suvPrice: 1350,
    vanPrice: 1700,
    currency: 'THB',
    isActive: true,
  },
  {
    id: 4,
    minKm: 101,
    maxKm: 145,
    sedanPrice: 1300,
    suvPrice: 1600,
    vanPrice: 2000,
    currency: 'THB',
    isActive: true,
  },
  {
    id: 5,
    minKm: 146,
    maxKm: 200,
    sedanPrice: 1400,
    suvPrice: 1700,
    vanPrice: 2100,
    currency: 'THB',
    isActive: true,
  },
];

const SERVICE_TYPES = [
  { id: 1, code: 'AIRPORT_PICKUP' },
  { id: 2, code: 'AIRPORT_DROPOFF' },
  { id: 3, code: 'CITY_TRANSFER' },
  { id: 4, code: 'GOLF_TRANSFER' },
];

const LOCATIONS = [
  { id: 3, code: 'PATTAYA', type: 'CITY' },
  { id: 4, code: 'BANGKOK', type: 'CITY' },
];

const CITY_TRANSFER_ROUTE = {
  id: 50,
  serviceTypeId: 3,
  originLocationId: 4,
  destinationLocationId: 3,
  isActive: true,
  effectiveFrom: null,
  effectiveTo: null,
};

const CITY_TRANSFER_PRICE = {
  id: 500,
  routeId: 50,
  vehicleTypeId: 3,
  price: 2000,
  currency: 'THB',
  isActive: true,
  effectiveFrom: null,
  effectiveTo: null,
};

const COORDS = {
  bangkok: { lat: 13.7563, lng: 100.5018 },
  mediumTrip: { lat: 13.9813, lng: 100.5018 },
  shortTrip: { lat: 13.80, lng: 100.5018 },
  longTrip: { lat: 18.0, lng: 100.5018 },
};

function makeDistanceBandRepository() {
  return {
    async findActiveBandByDistance(distanceKm) {
      return DISTANCE_BANDS.find(
        (band) => band.isActive
          && band.minKm <= distanceKm
          && (band.maxKm == null || band.maxKm >= distanceKm),
      ) ?? null;
    },
    async findAll() {
      return DISTANCE_BANDS;
    },
  };
}

function makeCityTransferPricingService() {
  return new CityTransferDistancePricingService(makeDistanceBandRepository());
}

function makePricingServiceWithDistanceFallback(options = {}) {
  const routes = options.routes ?? [CITY_TRANSFER_ROUTE];
  const prices = options.prices ?? [CITY_TRANSFER_PRICE];

  return new PricingService(
    {
      async findByCode(code) {
        return SERVICE_TYPES.find((row) => row.code === code) ?? null;
      },
      async findById(id) {
        return SERVICE_TYPES.find((row) => row.id === id) ?? null;
      },
    },
    {
      async findById(id) {
        return LOCATIONS.find((row) => row.id === Number(id)) ?? null;
      },
      async findByCode(code) {
        return LOCATIONS.find((row) => row.code === code) ?? null;
      },
      async findByAirportIata() {
        return null;
      },
    },
    {
      async findActiveByServiceAndLocations(serviceTypeId, originLocationId, destinationLocationId) {
        return routes.filter((route) => route.serviceTypeId === serviceTypeId
          && route.originLocationId === originLocationId
          && route.destinationLocationId === destinationLocationId
          && route.isActive);
      },
    },
    {
      async findByRouteId(routeId) {
        return prices.filter((price) => price.routeId === routeId);
      },
    },
    {
      async findActivePolicies() {
        return [];
      },
    },
    {
      async findTypeByCode(code) {
        const map = {
          SEDAN: { id: 1, code: 'SEDAN' },
          SUV: { id: 2, code: 'SUV' },
          VAN: { id: 3, code: 'VAN' },
          VIP_VAN: { id: 4, code: 'VIP_VAN' },
        };
        return map[code] ?? null;
      },
    },
    options.distanceService ?? makeCityTransferPricingService(),
  );
}

test('estimateRoadDistanceKm applies correction factor to haversine distance', () => {
  const estimated = estimateRoadDistanceKm(
    COORDS.bangkok.lat,
    COORDS.bangkok.lng,
    COORDS.mediumTrip.lat,
    COORDS.mediumTrip.lng,
  );
  assert.ok(estimated >= 13 && estimated <= 50);
});

test('city transfer distance pricing returns band price within auto-quote range', async () => {
  const service = makeCityTransferPricingService();
  const result = await service.calculateByDistance(
    COORDS.bangkok.lat,
    COORDS.bangkok.lng,
    COORDS.mediumTrip.lat,
    COORDS.mediumTrip.lng,
    'SEDAN',
  );

  assert.equal(result.price, 900);
  assert.equal(result.band.id, 2);
  assert.ok(result.estimatedDistanceKm >= 13);
  assert.ok(result.estimatedDistanceKm <= 50);
});

test('city transfer distance pricing rejects short trips with INQUIRY_REQUIRED', async () => {
  const service = makeCityTransferPricingService();
  await assert.rejects(
    () => service.calculateByDistance(
      COORDS.bangkok.lat,
      COORDS.bangkok.lng,
      COORDS.shortTrip.lat,
      COORDS.shortTrip.lng,
      'SUV',
    ),
    (err) => err.errorCode === ERROR_CODES.INQUIRY_REQUIRED,
  );
});

test('city transfer distance pricing rejects long trips with INQUIRY_REQUIRED', async () => {
  const service = makeCityTransferPricingService();
  await assert.rejects(
    () => service.calculateByDistance(
      COORDS.bangkok.lat,
      COORDS.bangkok.lng,
      COORDS.longTrip.lat,
      COORDS.longTrip.lng,
      'VAN',
    ),
    (err) => err.errorCode === ERROR_CODES.INQUIRY_REQUIRED,
  );
});

test('city transfer distance pricing rejects unsupported vehicle types', async () => {
  const service = makeCityTransferPricingService();
  await assert.rejects(
    () => service.calculateByDistance(
      COORDS.bangkok.lat,
      COORDS.bangkok.lng,
      COORDS.mediumTrip.lat,
      COORDS.mediumTrip.lng,
      'VIP_VAN',
    ),
    (err) => err.errorCode === ERROR_CODES.INQUIRY_REQUIRED,
  );
});

test('CITY_TRANSFER fixed route match still uses table price when location codes resolve', async () => {
  const pricingService = makePricingServiceWithDistanceFallback();
  const result = await pricingService.calculate({
    serviceTypeCode: 'CITY_TRANSFER',
    vehicleTypeCode: 'VAN',
    originLocationCode: 'BANGKOK',
    destinationLocationCode: 'PATTAYA',
    originLat: COORDS.bangkok.lat,
    originLng: COORDS.bangkok.lng,
    destinationLat: COORDS.mediumTrip.lat,
    destinationLng: COORDS.mediumTrip.lng,
  });

  assert.equal(result.totalAmount, 2000);
  assert.equal(result.routeId, 50);
  assert.equal(result.vehiclePriceId, 500);
});

test('CITY_TRANSFER falls back to distance band pricing when route match fails', async () => {
  const pricingService = makePricingServiceWithDistanceFallback({ routes: [], prices: [] });
  const result = await pricingService.calculate({
    serviceTypeCode: 'CITY_TRANSFER',
    vehicleTypeCode: 'SEDAN',
    originLocationCode: 'BANGKOK',
    destinationRegion: 'Solyn Hotel',
    originLat: COORDS.bangkok.lat,
    originLng: COORDS.bangkok.lng,
    destinationLat: COORDS.mediumTrip.lat,
    destinationLng: COORDS.mediumTrip.lng,
  });

  assert.equal(result.totalAmount, 900);
  assert.equal(result.routeId, null);
  assert.equal(result.vehiclePriceId, null);
  assert.equal(result.appliedPricingRuleId, 2);
  assert.equal(result.chargeItems[0].referenceType, 'CITY_TRANSFER_DISTANCE_BAND');
});

test('CITY_TRANSFER without coordinates keeps NOT_FOUND when route match fails', async () => {
  const pricingService = makePricingServiceWithDistanceFallback({ routes: [], prices: [] });
  await assert.rejects(
    () => pricingService.calculate({
      serviceTypeCode: 'CITY_TRANSFER',
      vehicleTypeCode: 'SEDAN',
      originLocationCode: 'BANGKOK',
      destinationRegion: 'Solyn Hotel',
    }),
    (err) => err.errorCode === ERROR_CODES.NOT_FOUND,
  );
});

test('AIRPORT_PICKUP does not use city transfer distance fallback', async () => {
  const pricingService = makePricingServiceWithDistanceFallback({ routes: [], prices: [] });
  await assert.rejects(
    () => pricingService.calculate({
      serviceTypeCode: 'AIRPORT_PICKUP',
      vehicleTypeCode: 'SEDAN',
      originAirportIata: 'BKK',
      destinationRegion: 'Solyn Hotel',
      originLat: COORDS.bangkok.lat,
      originLng: COORDS.bangkok.lng,
      destinationLat: COORDS.mediumTrip.lat,
      destinationLng: COORDS.mediumTrip.lng,
    }),
    (err) => err.errorCode === ERROR_CODES.NOT_FOUND,
  );
});

test('GOLF_TRANSFER does not use city transfer distance fallback', async () => {
  const pricingService = makePricingServiceWithDistanceFallback({ routes: [], prices: [] });
  await assert.rejects(
    () => pricingService.calculate({
      serviceTypeCode: 'GOLF_TRANSFER',
      vehicleTypeCode: 'SEDAN',
      originLocationCode: 'BANGKOK',
      destinationRegion: 'Solyn Hotel',
      originLat: COORDS.bangkok.lat,
      originLng: COORDS.bangkok.lng,
      destinationLat: COORDS.mediumTrip.lat,
      destinationLng: COORDS.mediumTrip.lng,
    }),
    (err) => err.errorCode === ERROR_CODES.NOT_FOUND,
  );
});

test('CITY_TRANSFER distance fallback returns INQUIRY_REQUIRED for out-of-range trips', async () => {
  const pricingService = makePricingServiceWithDistanceFallback({ routes: [], prices: [] });
  await assert.rejects(
    () => pricingService.calculate({
      serviceTypeCode: 'CITY_TRANSFER',
      vehicleTypeCode: 'SEDAN',
      originLocationCode: 'BANGKOK',
      destinationRegion: 'Nearby stop',
      originLat: COORDS.bangkok.lat,
      originLng: COORDS.bangkok.lng,
      destinationLat: COORDS.shortTrip.lat,
      destinationLng: COORDS.shortTrip.lng,
    }),
    (err) => err.errorCode === ERROR_CODES.INQUIRY_REQUIRED,
  );
});

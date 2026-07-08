process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const PricingService = require('../src/services/pricing.service');
const ERROR_CODES = require('../src/constants/errorCodes');

const FARE_TABLE = [
  { service: 'AIRPORT_PICKUP', origin: 'BKK', dest: 'PATTAYA', vehicle: 'SEDAN', price: 1000 },
  { service: 'AIRPORT_PICKUP', origin: 'BKK', dest: 'PATTAYA', vehicle: 'SUV', price: 1300 },
  { service: 'AIRPORT_PICKUP', origin: 'BKK', dest: 'PATTAYA', vehicle: 'VAN', price: 1700 },
  { service: 'AIRPORT_PICKUP', origin: 'BKK', dest: 'BANGKOK', vehicle: 'SEDAN', price: 550 },
  { service: 'AIRPORT_PICKUP', origin: 'BKK', dest: 'HUA_HIN', vehicle: 'VAN', price: 2700 },
  { service: 'AIRPORT_PICKUP', origin: 'DMK', dest: 'PATTAYA', vehicle: 'VAN', price: 2200 },
  { service: 'AIRPORT_DROPOFF', origin: 'PATTAYA', dest: 'DMK', vehicle: 'VAN', price: 2300 },
  { service: 'CITY_TRANSFER', origin: 'PATTAYA', dest: 'BANGKOK', vehicle: 'SUV', price: 1500 },
  { service: 'CITY_TRANSFER', origin: 'BANGKOK', dest: 'PATTAYA', vehicle: 'VAN', price: 2000 },
  { service: 'AIRPORT_DROPOFF', origin: 'BANGKOK', dest: 'BKK', vehicle: 'SUV', price: 800 },
];

const SERVICE_TYPES = [
  { id: 1, code: 'AIRPORT_PICKUP' },
  { id: 2, code: 'AIRPORT_DROPOFF' },
  { id: 3, code: 'CITY_TRANSFER' },
];

const LOCATIONS = [
  { id: 1, code: 'BKK', type: 'AIRPORT' },
  { id: 2, code: 'DMK', type: 'AIRPORT' },
  { id: 3, code: 'PATTAYA', type: 'CITY' },
  { id: 4, code: 'BANGKOK', type: 'CITY' },
  { id: 5, code: 'HUA_HIN', type: 'CITY' },
  { id: 6, code: 'RAYONG', type: 'CITY' },
  { id: 7, code: 'AYUTTHAYA', type: 'CITY' },
];

const VEHICLE_TYPES = {
  SEDAN: { id: 1, code: 'SEDAN' },
  SUV: { id: 2, code: 'SUV' },
  VAN: { id: 3, code: 'VAN' },
  LUXURY: { id: 4, code: 'LUXURY' },
};

function locationId(code) {
  return LOCATIONS.find((row) => row.code === code)?.id;
}

function buildFareTablePricingService() {
  let routeId = 1;
  let priceId = 1;
  const routes = [];
  const prices = [];
  const routeKeyToId = new Map();

  for (const row of FARE_TABLE) {
    const key = `${row.service}:${row.origin}:${row.dest}`;
    if (!routeKeyToId.has(key)) {
      const serviceType = SERVICE_TYPES.find((st) => st.code === row.service);
      routeKeyToId.set(key, routeId);
      routes.push({
        id: routeId,
        serviceTypeId: serviceType.id,
        serviceTypeCode: row.service,
        originLocationId: locationId(row.origin),
        destinationLocationId: locationId(row.dest),
        isActive: true,
        effectiveFrom: null,
        effectiveTo: null,
      });
      routeId += 1;
    }
    const currentRouteId = routeKeyToId.get(key);
    const vehicleType = VEHICLE_TYPES[row.vehicle];
    prices.push({
      id: priceId,
      routeId: currentRouteId,
      vehicleTypeId: vehicleType.id,
      price: row.price,
      currency: 'THB',
      isActive: true,
      effectiveFrom: null,
      effectiveTo: null,
    });
    priceId += 1;
  }

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
      async findByAirportIata(iata) {
        return LOCATIONS.find((row) => row.code === iata) ?? null;
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
        return VEHICLE_TYPES[code] ?? null;
      },
    },
  );
}

const pricingService = buildFareTablePricingService();

const fareCases = [
  {
    label: 'BKK → Pattaya SUV',
    input: {
      serviceTypeCode: 'AIRPORT_PICKUP',
      vehicleTypeCode: 'SUV',
      originAirportIata: 'BKK',
      destinationLocationCode: 'PATTAYA',
    },
    expected: 1300,
  },
  {
    label: 'BKK → Bangkok Sedan',
    input: {
      serviceTypeCode: 'AIRPORT_PICKUP',
      vehicleTypeCode: 'SEDAN',
      originAirportIata: 'BKK',
      destinationLocationCode: 'BANGKOK',
    },
    expected: 550,
  },
  {
    label: 'BKK → Hua Hin VAN',
    input: {
      serviceTypeCode: 'AIRPORT_PICKUP',
      vehicleTypeCode: 'VAN',
      originAirportIata: 'BKK',
      destinationLocationCode: 'HUA_HIN',
    },
    expected: 2700,
  },
  {
    label: 'DMK → Pattaya VAN',
    input: {
      serviceTypeCode: 'AIRPORT_PICKUP',
      vehicleTypeCode: 'VAN',
      originAirportIata: 'DMK',
      destinationLocationCode: 'PATTAYA',
    },
    expected: 2200,
  },
  {
    label: 'Pattaya → DMK VAN',
    input: {
      serviceTypeCode: 'AIRPORT_DROPOFF',
      vehicleTypeCode: 'VAN',
      originLocationCode: 'PATTAYA',
      destinationLocationCode: 'DMK',
    },
    expected: 2300,
  },
  {
    label: 'Pattaya → Bangkok SUV',
    input: {
      serviceTypeCode: 'CITY_TRANSFER',
      vehicleTypeCode: 'SUV',
      originLocationCode: 'PATTAYA',
      destinationLocationCode: 'BANGKOK',
    },
    expected: 1500,
  },
  {
    label: 'Bangkok → Pattaya VAN',
    input: {
      serviceTypeCode: 'CITY_TRANSFER',
      vehicleTypeCode: 'VAN',
      originLocationCode: 'BANGKOK',
      destinationLocationCode: 'PATTAYA',
    },
    expected: 2000,
  },
  {
    label: 'Bangkok → BKK Airport SUV',
    input: {
      serviceTypeCode: 'AIRPORT_DROPOFF',
      vehicleTypeCode: 'SUV',
      originLocationCode: 'BANGKOK',
      destinationLocationCode: 'BKK',
    },
    expected: 800,
  },
];

for (const fareCase of fareCases) {
  test(`fare table image seed pricing: ${fareCase.label}`, async () => {
    const result = await pricingService.calculate(fareCase.input);
    assert.equal(result.totalAmount, fareCase.expected);
  });
}

test('fare table: route outside image returns not found (inquiry path)', async () => {
  await assert.rejects(
    () => pricingService.calculate({
      serviceTypeCode: 'CITY_TRANSFER',
      vehicleTypeCode: 'SEDAN',
      originLocationCode: 'BANGKOK',
      destinationLocationCode: 'HUA_HIN',
    }),
    (err) => err.errorCode === ERROR_CODES.NOT_FOUND
      && /Route not found/.test(err.message),
  );
});

test('fare table: vehicle outside image returns vehicle price not configured', async () => {
  await assert.rejects(
    () => pricingService.calculate({
      serviceTypeCode: 'AIRPORT_PICKUP',
      vehicleTypeCode: 'LUXURY',
      originAirportIata: 'BKK',
      destinationLocationCode: 'PATTAYA',
    }),
    (err) => err.errorCode === ERROR_CODES.NOT_FOUND
      && /Vehicle price not configured/.test(err.message),
  );
});

test('fare table: BKK pickup Pattaya sedan still resolves after image seed prices', async () => {
  const result = await pricingService.calculate({
    serviceTypeCode: 'AIRPORT_PICKUP',
    vehicleTypeCode: 'SEDAN',
    originAirportIata: 'BKK',
    destinationLocationCode: 'PATTAYA',
  });
  assert.equal(result.totalAmount, 1000);
});

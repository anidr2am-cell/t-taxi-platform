const { test } = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const CHARGE_POLICY_TYPES = require('../src/constants/chargePolicyTypes');
const CHARGE_TYPES = require('../src/constants/chargeTypes');
const PricingService = require('../src/services/pricing.service');

const sampleRoute = {
  id: 10,
  serviceTypeId: 1,
  originLocationId: 1,
  destinationLocationId: 8,
  isActive: true,
  effectiveFrom: null,
  effectiveTo: null,
};

const samplePrice = {
  id: 20,
  routeId: 10,
  vehicleTypeId: 2,
  price: 1000,
  currency: 'THB',
  isActive: true,
  effectiveFrom: null,
  effectiveTo: null,
};

const activePolicies = [
  {
    id: 1,
    chargeType: CHARGE_POLICY_TYPES.NAME_SIGN,
    calculationType: 'FIXED',
    amount: 100,
    isActive: true,
    effectiveFrom: null,
    effectiveTo: null,
  },
  {
    id: 2,
    chargeType: CHARGE_POLICY_TYPES.AIRPORT,
    calculationType: 'FIXED',
    amount: 50,
    isActive: true,
    effectiveFrom: null,
    effectiveTo: null,
  },
  {
    id: 3,
    chargeType: CHARGE_POLICY_TYPES.NIGHT,
    calculationType: 'PERCENT_OF_BASE',
    amount: 15,
    isActive: true,
    effectiveFrom: null,
    effectiveTo: null,
  },
];

function createPricingService() {
  return new PricingService(
    {
      async findByCode(code) {
        return code === 'AIRPORT_PICKUP' ? { id: 1, code } : null;
      },
      async findById(id) {
        return id === 1 ? { id: 1, code: 'AIRPORT_PICKUP' } : null;
      },
    },
    {
      async findById(id) {
        if (id === 1) return { id: 1, code: 'BKK' };
        if (id === 8) return { id: 8, code: 'PATTAYA' };
        return null;
      },
      async findByCode(code) {
        if (code === 'BKK') return { id: 1, code: 'BKK' };
        if (code === 'PATTAYA') return { id: 8, code: 'PATTAYA' };
        return null;
      },
      async findByAirportIata(iata) {
        return iata === 'BKK' ? { id: 1, code: 'BKK' } : null;
      },
    },
    {
      async findActiveByServiceAndLocations() {
        return [sampleRoute];
      },
    },
    {
      async findByRouteId() {
        return [samplePrice];
      },
    },
    {
      async findActivePolicies() {
        return activePolicies;
      },
    },
    {
      async findTypeById(id) {
        return id === 2 ? { id: 2, code: 'SUV' } : null;
      },
      async findTypeByCode(code) {
        return code === 'SUV' ? { id: 2, code: 'SUV' } : null;
      },
    },
  );
}

test('customer calculate excludes night and airport surcharges but keeps name sign', async () => {
  const pricingService = createPricingService();
  const nightPickup = '2099-07-01T22:30:00.000Z';

  const quote = await pricingService.calculate({
    serviceTypeCode: 'AIRPORT_PICKUP',
    originAirportIata: 'BKK',
    destinationLocationCode: 'PATTAYA',
    vehicleTypeCode: 'SUV',
    scheduledPickupAt: nightPickup,
    options: { nameSign: true },
  });

  const chargeTypes = quote.chargeItems.map((item) => item.chargeType);
  assert.deepEqual(chargeTypes, [CHARGE_TYPES.VEHICLE_BASE, CHARGE_TYPES.NAME_SIGN]);
  assert.equal(quote.totalAmount, 1100);
  assert.equal(quote.currency, 'THB');
});

test('admin simulate still includes night and airport surcharges', async () => {
  const pricingService = createPricingService();
  const nightPickup = '2099-07-01T22:30:00.000Z';

  const quote = await pricingService.simulate({
    serviceType: 'AIRPORT_PICKUP',
    originLocationId: 1,
    destinationLocationId: 8,
    vehicleTypeId: 2,
    scheduledPickupAt: nightPickup,
    options: { nameSign: true },
  });

  const chargeTypes = quote.chargeItems.map((item) => item.chargeType);
  assert.ok(chargeTypes.includes(CHARGE_TYPES.NIGHT_SURCHARGE));
  assert.ok(chargeTypes.includes(CHARGE_TYPES.AIRPORT_SURCHARGE));
  assert.ok(chargeTypes.includes(CHARGE_TYPES.NAME_SIGN));
  assert.equal(quote.totalAmount, 1300);
});

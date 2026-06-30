process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const request = require('supertest');

const app = require('../src/app');
const container = require('../src/helpers/container');
const PricingAdminService = require('../src/services/pricingAdmin.service');
const RouteAdminService = require('../src/services/routeAdmin.service');
const PricingService = require('../src/services/pricing.service');
const ERROR_CODES = require('../src/constants/errorCodes');

function sign(role = 'ADMIN', id = 1) {
  return jwt.sign(
    { sub: id, email: `${role.toLowerCase()}@example.com`, role, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

const sampleRoute = {
  id: 1,
  serviceTypeId: 1,
  serviceTypeCode: 'AIRPORT_PICKUP',
  originLocationId: 1,
  originLocationCode: 'BKK',
  originDisplayName: 'Suvarnabhumi',
  destinationLocationId: 8,
  destinationLocationCode: 'PATTAYA',
  destinationDisplayName: 'Pattaya',
  isActive: true,
  displayOrder: 0,
  effectiveFrom: null,
  effectiveTo: null,
  createdAt: '2026-01-01T00:00:00.000Z',
  updatedAt: '2026-01-01T00:00:00.000Z',
};

const samplePrice = {
  id: 10,
  routeId: 1,
  vehicleTypeId: 1,
  vehicleTypeCode: 'SEDAN',
  price: 800,
  currency: 'THB',
  isActive: true,
  effectiveFrom: null,
  effectiveTo: null,
  createdAt: '2026-01-01T00:00:00.000Z',
  updatedAt: '2026-01-01T00:00:00.000Z',
};

const samplePolicy = {
  id: 20,
  chargeType: 'NIGHT',
  calculationType: 'PERCENT_OF_BASE',
  amount: 10,
  isActive: true,
  effectiveFrom: null,
  effectiveTo: null,
  createdAt: '2026-01-01T00:00:00.000Z',
  updatedAt: '2026-01-01T00:00:00.000Z',
};

function registerPricingMocks(overrides = {}) {
  container.register('pricingAdminService', () => ({
    async getSummary() {
      return {
        activeRouteCount: 1,
        activeVehiclePriceCount: 1,
        activeChargePolicyCount: 1,
        currentPriceCount: 1,
        expiringSoonPriceCount: 0,
        updatedAt: '2026-06-29T05:00:00.000Z',
      };
    },
  }));

  container.register('routeAdminService', () => ({
    async list() {
      return overrides.routes ?? [sampleRoute];
    },
    async getById(id) {
      const route = (overrides.routes ?? [sampleRoute]).find((row) => row.id === id);
      if (!route) throw new Error('not found');
      return route;
    },
    async create(input) {
      if (overrides.createRouteError) throw overrides.createRouteError;
      return { ...sampleRoute, ...input, id: 99 };
    },
    async update(id, input) {
      return { ...sampleRoute, id, ...input };
    },
    async delete() {
      return true;
    },
    async copy() {
      return { route: { ...sampleRoute, id: 100 }, copiedVehiclePriceCount: 2 };
    },
  }));

  container.register('vehiclePriceAdminService', () => ({
    async list() {
      return overrides.prices ?? [samplePrice];
    },
    async getById(id) {
      return { ...samplePrice, id };
    },
    async create(input) {
      if (overrides.createPriceError) throw overrides.createPriceError;
      return { ...samplePrice, ...input, id: 101 };
    },
    async update(id, input) {
      return { ...samplePrice, id, ...input };
    },
    async delete() {
      return true;
    },
  }));

  container.register('chargePolicyAdminService', () => ({
    async list() {
      return overrides.policies ?? [samplePolicy];
    },
    async getById(id) {
      return { ...samplePolicy, id };
    },
    async create(input) {
      return { ...samplePolicy, ...input, id: 102 };
    },
    async update(id, input) {
      return { ...samplePolicy, id, ...input };
    },
    async delete() {
      return true;
    },
  }));

  container.register('pricingService', () => ({
    async simulate() {
      return {
        matchedRoute: sampleRoute,
        vehicleBasePrice: samplePrice,
        chargeItems: [{ chargeType: 'VEHICLE_BASE', amount: 800 }],
        subtotal: 800,
        discount: 0,
        totalAmount: 800,
        currency: 'THB',
      };
    },
    async calculate() {
      return {
        currency: 'THB',
        chargeItems: [{ chargeType: 'VEHICLE_BASE', amount: 800 }],
        totalAmount: 800,
        routeId: 1,
        vehiclePriceId: 10,
      };
    },
  }));
}

test('ADMIN can read pricing summary', async () => {
  registerPricingMocks();
  const res = await request(app)
    .get('/api/v1/admin/pricing/summary')
    .set('Authorization', `Bearer ${sign('ADMIN')}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.data.activeRouteCount, 1);
  assert.equal(res.body.data.currentPriceCount, 1);
});

test('SUPER_ADMIN can list routes and vehicle prices', async () => {
  registerPricingMocks();
  const routes = await request(app)
    .get('/api/v1/admin/routes?includeInactive=true')
    .set('Authorization', `Bearer ${sign('SUPER_ADMIN')}`);
  assert.equal(routes.status, 200);
  assert.equal(routes.body.data.length, 1);
  assert.equal(routes.body.data[0].originLocationCode, 'BKK');

  const prices = await request(app)
    .get('/api/v1/admin/vehicle-prices?includeInactive=true')
    .set('Authorization', `Bearer ${sign('SUPER_ADMIN')}`);
  assert.equal(prices.status, 200);
  assert.equal(prices.body.data[0].vehicleTypeCode, 'SEDAN');
});

test('DRIVER and unauthenticated admin pricing requests are rejected', async () => {
  registerPricingMocks();
  const driver = await request(app)
    .get('/api/v1/admin/pricing/summary')
    .set('Authorization', `Bearer ${sign('DRIVER', 9)}`);
  assert.equal(driver.status, 403);

  const unauthenticated = await request(app).get('/api/v1/admin/routes');
  assert.equal(unauthenticated.status, 401);
});

test('route create rejects duplicate service/origin/destination', async () => {
  const AppError = require('../src/utils/AppError');
  const HTTP_STATUS = require('../src/constants/httpStatus');
  registerPricingMocks({
    createRouteError: new AppError('Route already exists for this service, origin, and destination', {
      statusCode: HTTP_STATUS.BAD_REQUEST,
      errorCode: ERROR_CODES.VALIDATION_ERROR,
    }),
  });

  const res = await request(app)
    .post('/api/v1/admin/routes')
    .set('Authorization', `Bearer ${sign('ADMIN')}`)
    .send({
      serviceTypeCode: 'AIRPORT_PICKUP',
      originLocationCode: 'BKK',
      destinationLocationCode: 'PATTAYA',
    });

  assert.equal(res.status, 400);
  assert.match(res.body.message, /already exists/i);
});

test('route create validation rejects origin equal to destination', async () => {
  const service = new RouteAdminService(
    {
      async create() { return sampleRoute; },
      async findById() { return sampleRoute; },
    },
    { async findByRouteId() { return []; } },
    {
      async findById() { return { id: 1, code: 'AIRPORT_PICKUP' }; },
      async findByCode() { return { id: 1, code: 'AIRPORT_PICKUP' }; },
    },
    {
      async findById(id) { return { id, code: 'BKK' }; },
      async findByCode() { return { id: 1, code: 'BKK' }; },
    },
  );

  await assert.rejects(
    () => service.create({
      serviceTypeCode: 'AIRPORT_PICKUP',
      originLocationCode: 'BKK',
      destinationLocationCode: 'BKK',
    }, 1),
    (err) => err.message.includes('Origin and destination must be different'),
  );
});

test('route can be deactivated via PATCH', async () => {
  registerPricingMocks();
  const res = await request(app)
    .patch('/api/v1/admin/routes/1')
    .set('Authorization', `Bearer ${sign('ADMIN')}`)
    .send({ isActive: false });

  assert.equal(res.status, 200);
  assert.equal(res.body.data.isActive, false);
});

test('route copy endpoint returns copied route payload', async () => {
  registerPricingMocks();
  const res = await request(app)
    .post('/api/v1/admin/routes/1/copy')
    .set('Authorization', `Bearer ${sign('ADMIN')}`)
    .send({
      originLocationId: 1,
      destinationLocationCode: 'BANGKOK',
    });

  assert.equal(res.status, 201);
  assert.equal(res.body.data.copiedVehiclePriceCount, 2);
  assert.ok(res.body.data.route);
});

test('vehicle price create rejects invalid price via validation', async () => {
  registerPricingMocks();
  const res = await request(app)
    .post('/api/v1/admin/vehicle-prices')
    .set('Authorization', `Bearer ${sign('ADMIN')}`)
    .send({
      routeId: 1,
      vehicleTypeCode: 'SEDAN',
      price: -10,
      currency: 'THB',
    });

  assert.equal(res.status, 400);
  assert.equal(res.body.error_code, ERROR_CODES.VALIDATION_ERROR);
  assert.ok(Array.isArray(res.body.errors));
});

test('vehicle price update accepts effective period fields', async () => {
  registerPricingMocks();
  const res = await request(app)
    .patch('/api/v1/admin/vehicle-prices/10')
    .set('Authorization', `Bearer ${sign('ADMIN')}`)
    .send({
      effectiveFrom: '2026-07-01T00:00:00.000Z',
      effectiveTo: '2026-12-31T23:59:59.000Z',
    });

  assert.equal(res.status, 200);
  assert.equal(res.body.data.effectiveFrom, '2026-07-01T00:00:00.000Z');
});

test('pricing summary classifies current and expiring prices', async () => {
  const now = new Date('2026-06-29T12:00:00.000Z');
  const service = new PricingAdminService(
    {
      async findAll() {
        return [{ ...sampleRoute, isActive: true }];
      },
    },
    {
      async findAll() {
        return [
          { ...samplePrice, isActive: true, effectiveFrom: null, effectiveTo: null },
          {
            ...samplePrice,
            id: 11,
            isActive: true,
            effectiveFrom: '2026-07-01T00:00:00.000Z',
            effectiveTo: null,
          },
          {
            ...samplePrice,
            id: 12,
            isActive: true,
            effectiveFrom: null,
            effectiveTo: '2026-07-10T00:00:00.000Z',
          },
          { ...samplePrice, id: 13, isActive: false },
        ];
      },
    },
    {
      async findAll() {
        return [{ ...samplePolicy, isActive: true }];
      },
    },
  );

  const originalDate = Date;
  global.Date = class extends Date {
    constructor(...args) {
      if (args.length === 0) {
        super(now.getTime());
      } else {
        super(...args);
      }
    }

    static now() {
      return now.getTime();
    }
  };

  try {
    const summary = await service.getSummary();
    assert.equal(summary.activeRouteCount, 1);
    assert.equal(summary.activeVehiclePriceCount, 3);
    assert.equal(summary.currentPriceCount, 2);
    assert.equal(summary.expiringSoonPriceCount, 1);
  } finally {
    global.Date = originalDate;
  }
});

test('charge policy CRUD endpoints work for admin', async () => {
  registerPricingMocks();
  const list = await request(app)
    .get('/api/v1/admin/charge-policies')
    .set('Authorization', `Bearer ${sign('ADMIN')}`);
  assert.equal(list.status, 200);

  const created = await request(app)
    .post('/api/v1/admin/charge-policies')
    .set('Authorization', `Bearer ${sign('ADMIN')}`)
    .send({
      chargeType: 'NAME_SIGN',
      calculationType: 'FIXED',
      amount: 150,
    });
  assert.equal(created.status, 201);

  const updated = await request(app)
    .patch('/api/v1/admin/charge-policies/20')
    .set('Authorization', `Bearer ${sign('ADMIN')}`)
    .send({ isActive: false });
  assert.equal(updated.status, 200);
  assert.equal(updated.body.data.isActive, false);
});

test('pricing simulate endpoint returns quote breakdown', async () => {
  registerPricingMocks();
  const res = await request(app)
    .post('/api/v1/admin/pricing/simulate')
    .set('Authorization', `Bearer ${sign('ADMIN')}`)
    .send({
      serviceType: 'AIRPORT_PICKUP',
      originLocationId: 1,
      destinationLocationId: 8,
      vehicleTypeId: 1,
    });

  assert.equal(res.status, 200);
  assert.equal(res.body.data.totalAmount, 800);
  assert.equal(res.body.data.currency, 'THB');
  assert.ok(res.body.data.matchedRoute);
});

test('simulator and customer calculate share computeQuote totals', async () => {
  const pricingService = new PricingService(
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
      async findByAirportIata() { return null; },
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
        return [];
      },
    },
    {
      async findTypeById(id) {
        return id === 1 ? { id: 1, code: 'SEDAN' } : null;
      },
      async findTypeByCode(code) {
        return code === 'SEDAN' ? { id: 1, code: 'SEDAN' } : null;
      },
    },
  );

  const simulate = await pricingService.simulate({
    serviceType: 'AIRPORT_PICKUP',
    originLocationId: 1,
    destinationLocationId: 8,
    vehicleTypeId: 1,
  });
  const calculate = await pricingService.calculate({
    serviceTypeCode: 'AIRPORT_PICKUP',
    originLocationCode: 'BKK',
    destinationLocationCode: 'PATTAYA',
    vehicleTypeCode: 'SEDAN',
  });

  assert.equal(simulate.totalAmount, calculate.totalAmount);
  assert.equal(simulate.currency, calculate.currency);
});

test('empty pricing summary returns zeros safely', async () => {
  const service = new PricingAdminService(
    { async findAll() { return []; } },
    { async findAll() { return []; } },
    { async findAll() { return []; } },
  );

  const summary = await service.getSummary();
  assert.equal(summary.activeRouteCount, 0);
  assert.equal(summary.activeVehiclePriceCount, 0);
  assert.equal(summary.activeChargePolicyCount, 0);
  assert.equal(summary.currentPriceCount, 0);
  assert.equal(summary.expiringSoonPriceCount, 0);
});

test('admin pricing responses do not expose sensitive customer data', async () => {
  registerPricingMocks();
  const res = await request(app)
    .get('/api/v1/admin/routes')
    .set('Authorization', `Bearer ${sign('ADMIN')}`);

  const body = JSON.stringify(res.body);
  assert.ok(!body.includes('customerPhone'));
  assert.ok(!body.includes('password'));
  assert.ok(!/ER_/i.test(body));
});

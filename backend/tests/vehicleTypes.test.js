process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test, describe, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');

const app = require('../src/app');
const container = require('../src/helpers/container');
const VehicleService = require('../src/services/vehicle.service');

describe('Vehicle type public routes', () => {
  beforeEach(() => {
    container.register('vehicleService', () => ({
      async listTypes() {
        return [];
      },
    }));
  });

  test('GET /api/v1/vehicles/types returns active vehicle types without auth', async () => {
    container.register('vehicleService', () => ({
      async listTypes() {
        return [
          {
            id: 1,
            code: 'SEDAN',
            name: 'Sedan',
            passengerCapacity: 2,
            luggageCapacity: 2,
            isActive: true,
          },
        ];
      },
    }));

    const res = await request(app)
      .get('/api/v1/vehicles/types')
      .expect(200);

    assert.equal(res.body.success, true);
    assert.deepEqual(res.body.data, [
      {
        id: 1,
        code: 'SEDAN',
        name: 'Sedan',
        passengerCapacity: 2,
        luggageCapacity: 2,
        isActive: true,
      },
    ]);
  });
});

describe('VehicleService', () => {
  test('listTypes maps DB columns to camelCase response fields in repository order', async () => {
    const repository = {
      async findPublicTypesOrdered() {
        return [
          {
            id: 2,
            code: 'SUV',
            name: 'SUV',
            max_passengers: 3,
            max_luggage: 3,
            is_active: 1,
          },
          {
            id: 1,
            code: 'SEDAN',
            name: 'Sedan',
            max_passengers: 2,
            max_luggage: 2,
            is_active: 1,
          },
        ];
      },
    };

    const result = await new VehicleService(repository).listTypes();

    assert.deepEqual(result, [
      {
        id: 2,
        code: 'SUV',
        name: 'SUV',
        passengerCapacity: 3,
        luggageCapacity: 3,
        isActive: true,
      },
      {
        id: 1,
        code: 'SEDAN',
        name: 'Sedan',
        passengerCapacity: 2,
        luggageCapacity: 2,
        isActive: true,
      },
    ]);
  });

  test('repository query returns only active non-deleted public types ordered by id', async () => {
    let sql = '';
    const repository = container.get('vehicleRepository');
    const originalPool = repository.pool;
    repository.pool = {
      async query(query) {
        sql = query;
        return [[]];
      },
    };

    try {
      await repository.findPublicTypesOrdered();
    } finally {
      repository.pool = originalPool;
    }

    assert.match(sql, /WHERE is_active = 1 AND deleted_at IS NULL/);
    assert.match(sql, /ORDER BY id ASC/);
  });
});

const { test } = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const DriverProfileService = require('../src/services/driverProfile.service');
const ERROR_CODES = require('../src/constants/errorCodes');

function createProfileHarness(overrides = {}) {
  const conn = {
    committed: false,
    rolledBack: false,
    released: false,
    async beginTransaction() {},
    async commit() { this.committed = true; },
    async rollback() { this.rolledBack = true; },
    release() { this.released = true; },
  };
  const pool = {
    async getConnection() { return conn; },
  };
  const profileRow = {
    id: 7,
    user_id: 42,
    name: 'Somchai',
    phone: '+66812345678',
    email: 'driver@example.com',
    vehicle_id: 55,
    vehicle_type_id: 3,
    plate_number: 'ABC-1234',
    model_name: 'Camry',
    color: 'White',
    application_id: 9,
    vehicle_year: 2022,
    is_active: 1,
    ...overrides.profileRow,
  };
  const calls = { selfUpdates: [], vehicleUpdates: [], years: [] };
  const driverRepository = {
    async findProfileByUserId(userId) {
      assert.equal(userId, 42);
      return profileRow;
    },
    async findProfileByUserIdForUpdate(_conn, userId) {
      assert.equal(userId, 42);
      return profileRow;
    },
    async updateSelfProfile(_conn, payload) {
      calls.selfUpdates.push(payload);
    },
    async updatePrimaryVehicle(_conn, payload) {
      calls.vehicleUpdates.push(payload);
    },
    async updateApplicationVehicleYear(_conn, applicationId, year) {
      calls.years.push({ applicationId, year });
    },
    async findAvatarFileByUserId() {
      return null;
    },
  };
  const vehicleRepository = {
    async findTypeByCode(code) {
      return code === 'SUV' ? { id: 3, code: 'SUV', name: 'SUV' } : null;
    },
  };

  const service = new DriverProfileService(
    pool,
    driverRepository,
    vehicleRepository,
    null,
    null,
  );

  return { service, conn, calls, profileRow };
}

test('updateProfile updates only allowlisted driver fields for authenticated user', async () => {
  const { service, conn, calls } = createProfileHarness();

  const result = await service.updateProfile(42, {
    name: 'New Name',
    phone: '+66811112222',
    vehicleTypeCode: 'SUV',
    vehiclePlateNumber: 'XYZ-9999',
    vehicleYear: 2020,
    role: 'ADMIN',
    approvalStatus: 'APPROVED',
  });

  assert.equal(conn.committed, true);
  assert.equal(calls.selfUpdates.length, 1);
  assert.equal(calls.selfUpdates[0].name, 'New Name');
  assert.equal(calls.vehicleUpdates.length, 1);
  assert.equal(calls.vehicleUpdates[0].plateNumber, 'XYZ-9999');
  assert.deepEqual(calls.years, [{ applicationId: 9, year: 2020 }]);
  assert.equal(result.phone, '+66812345678');
});

test('updateProfile rejects invalid vehicle year', async () => {
  const { service } = createProfileHarness();

  await assert.rejects(
    () => service.updateProfile(42, { vehicleYear: 1800 }),
    (err) => err.errorCode === ERROR_CODES.VALIDATION_ERROR,
  );
});

test('updateProfile rejects invalid vehicle type code', async () => {
  const { service } = createProfileHarness();

  await assert.rejects(
    () => service.updateProfile(42, { vehicleTypeCode: 'NOT_A_TYPE' }),
    (err) => err.errorCode === ERROR_CODES.VALIDATION_ERROR,
  );
});

test('mapProfile returns null vehicle when no vehicle data exists', () => {
  const service = new DriverProfileService(null, {}, {}, null, null);
  const mapped = service.mapProfile({
    name: 'Somchai',
    phone: '+66812345678',
    email: 'driver@example.com',
    is_active: 1,
  });
  assert.equal(mapped.vehicle, null);
});

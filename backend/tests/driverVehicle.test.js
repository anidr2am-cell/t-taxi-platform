const { test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const os = require('os');
const fs = require('fs');

process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const DriverVehicleService = require('../src/services/driverVehicle.service');
const ERROR_CODES = require('../src/constants/errorCodes');

function touchTempImage(name) {
  const filePath = path.join(os.tmpdir(), `ttaxi-vehicle-${Date.now()}-${name}`);
  fs.writeFileSync(filePath, Buffer.from([0xff, 0xd8, 0xff, 0xd9]));
  return {
    path: filePath,
    originalname: name,
    filename: name,
    mimetype: 'image/jpeg',
    size: 4,
  };
}

function createHarness(overrides = {}) {
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

  const calls = {
    inserts: [],
    files: [],
    plateLookups: [],
  };

  const driverRepository = {
    async findByUserId(userId) {
      assert.equal(userId, 42);
      return overrides.driver ?? {
        id: 7,
        user_id: 42,
        is_active: 1,
        user_is_active: 1,
      };
    },
    async findByUserIdForUpdate(_conn, userId) {
      assert.equal(userId, 42);
      return overrides.driver ?? {
        id: 7,
        user_id: 42,
        is_active: 1,
        user_is_active: 1,
      };
    },
    async listVehiclesByDriverId(driverId) {
      assert.equal(driverId, 7);
      return overrides.listRows ?? [
        {
          id: 10,
          vehicle_type_id: 1,
          vehicle_type_code: 'SEDAN',
          vehicle_type_name: 'Sedan',
          plate_number: 'AAA-111',
          model_name: 'Camry',
          color: 'White',
          is_primary: 1,
          is_active: 1,
          approval_status: 'APPROVED',
          rejection_reason: null,
          created_at: '2026-07-01T00:00:00.000Z',
          updated_at: '2026-07-01T00:00:00.000Z',
          photo_count: 3,
          insurance_count: 1,
          registration_count: 1,
          tax_count: 0,
        },
        {
          id: 11,
          vehicle_type_id: 2,
          vehicle_type_code: 'SUV',
          vehicle_type_name: 'SUV',
          plate_number: 'BBB-222',
          model_name: 'Fortuner',
          color: 'Black',
          is_primary: 0,
          is_active: 0,
          approval_status: 'PENDING',
          rejection_reason: null,
          created_at: '2026-07-02T00:00:00.000Z',
          updated_at: '2026-07-02T00:00:00.000Z',
          photo_count: 3,
          insurance_count: 1,
          registration_count: 1,
          tax_count: 0,
        },
      ];
    },
    async findVehicleByPlateForUpdate(_conn, plate) {
      calls.plateLookups.push(plate);
      return overrides.existingPlate ?? null;
    },
    async insertPendingVehicle(_conn, payload) {
      calls.inserts.push(payload);
      return overrides.insertId ?? 99;
    },
    async insertVehicleFile(_conn, payload) {
      calls.files.push(payload);
    },
    async findVehicleByIdForDriver(driverId, vehicleId) {
      assert.equal(driverId, 7);
      assert.equal(vehicleId, overrides.insertId ?? 99);
      return {
        id: vehicleId,
        vehicle_type_id: 2,
        vehicle_type_code: 'SUV',
        vehicle_type_name: 'SUV',
        plate_number: 'NEW-9999',
        model_name: 'X',
        color: 'Red',
        is_primary: 0,
        is_active: 0,
        approval_status: 'PENDING',
        rejection_reason: null,
        created_at: '2026-07-25T00:00:00.000Z',
        updated_at: '2026-07-25T00:00:00.000Z',
        photo_count: 3,
        insurance_count: 1,
        registration_count: 1,
        tax_count: 0,
      };
    },
  };

  const vehicleRepository = {
    async findTypeById(id) {
      if (Number(id) === 2) return { id: 2, code: 'SUV', name: 'SUV' };
      return null;
    },
  };

  const fileRepository = {
    async insert(_conn, row) {
      return (calls.files.length || 0) + 1000;
    },
  };

  const service = new DriverVehicleService(
    pool,
    driverRepository,
    vehicleRepository,
    fileRepository,
  );
  return { service, conn, calls };
}

function validFiles() {
  return {
    vehiclePhotos: [
      touchTempImage('v1.jpg'),
      touchTempImage('v2.jpg'),
      touchTempImage('v3.jpg'),
    ],
    insuranceCertificate: [touchTempImage('ins.jpg')],
    vehicleRegistration: [touchTempImage('reg.jpg')],
    taxCertificate: [],
  };
}

test('listVehicles returns approved and pending statuses', async () => {
  const { service } = createHarness();
  const result = await service.listVehicles(42);
  assert.equal(result.items.length, 2);
  assert.equal(result.items[0].approvalStatus, 'APPROVED');
  assert.equal(result.items[0].isActive, true);
  assert.equal(result.items[1].approvalStatus, 'PENDING');
  assert.equal(result.items[1].isActive, false);
});

test('createVehicle stores pending inactive vehicle and keeps matching excluded', async () => {
  const { service, conn, calls } = createHarness();
  const created = await service.createVehicle(
    42,
    {
      vehicleTypeId: 2,
      plateNumber: 'NEW-9999',
      modelName: 'X',
      color: 'Red',
    },
    validFiles(),
  );

  assert.equal(conn.committed, true);
  assert.equal(calls.inserts.length, 1);
  assert.equal(calls.inserts[0].plateNumber, 'NEW-9999');
  // Matching uses is_active = 1; pending inserts must stay inactive.
  assert.equal(created.isActive, false);
  assert.equal(created.isPrimary, false);
  assert.equal(created.approvalStatus, 'PENDING');
  assert.ok(calls.files.length >= 5);
});

test('createVehicle rejects duplicate plate with friendly conflict', async () => {
  const { service } = createHarness({
    existingPlate: { id: 3, plate_number: 'DUP-1' },
  });
  await assert.rejects(
    () => service.createVehicle(
      42,
      { vehicleTypeId: 2, plateNumber: 'DUP-1' },
      validFiles(),
    ),
    (err) => err.statusCode === 409
      && err.errorCode === ERROR_CODES.VEHICLE_PLATE_ALREADY_REGISTERED,
  );
});

test('createVehicle maps unique constraint race to friendly conflict', async () => {
  const { service } = createHarness();
  service.driverRepository.insertPendingVehicle = async () => {
    const err = new Error('Duplicate');
    err.code = 'ER_DUP_ENTRY';
    throw err;
  };
  await assert.rejects(
    () => service.createVehicle(
      42,
      { vehicleTypeId: 2, plateNumber: 'RACE-1' },
      validFiles(),
    ),
    (err) => err.statusCode === 409
      && err.errorCode === ERROR_CODES.VEHICLE_PLATE_ALREADY_REGISTERED,
  );
});

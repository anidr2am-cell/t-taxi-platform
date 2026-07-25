const { test } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const request = require('supertest');

process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const DriverVehicleService = require('../src/services/driverVehicle.service');
const app = require('../src/app');
const ERROR_CODES = require('../src/constants/errorCodes');

function sign(role = 'ADMIN', id = 1) {
  return jwt.sign(
    {
      sub: id,
      email: `${role.toLowerCase()}@example.com`,
      role,
      type: 'access',
    },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

function createAdminHarness(overrides = {}) {
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
    listFilters: [],
    approve: [],
    reject: [],
    audits: [],
  };

  const pendingRow = overrides.pendingRow ?? {
    id: 55,
    driver_id: 7,
    driver_user_id: 42,
    driver_name: 'Kim Driver',
    plate_number: 'PEND-1',
    is_active: 0,
    approval_status: 'PENDING',
    rejection_reason: null,
  };

  const driverRepository = {
    async listVehiclesForAdmin(filters, pagination) {
      calls.listFilters.push({ filters, pagination });
      const all = overrides.listRows ?? [
        {
          id: 55,
          driver_id: 7,
          driver_user_id: 42,
          driver_name: 'Kim Driver',
          driver_phone: '010',
          vehicle_type_id: 2,
          vehicle_type_code: 'SUV',
          vehicle_type_name: 'SUV',
          plate_number: 'PEND-1',
          model_name: 'X',
          color: 'Black',
          is_primary: 0,
          is_active: 0,
          approval_status: 'PENDING',
          rejection_reason: null,
          created_at: '2026-07-20T00:00:00.000Z',
          updated_at: '2026-07-20T00:00:00.000Z',
          files_json: JSON.stringify([
            {
              id: 901,
              category: 'DRIVER_VEHICLE_PHOTO',
              sortOrder: 1,
              originalFilename: 'a.jpg',
              mimeType: 'image/jpeg',
              fileSize: 10,
              url: '/api/v1/admin/driver-vehicles/55/files/901',
            },
          ]),
        },
        {
          id: 56,
          driver_id: 7,
          driver_user_id: 42,
          driver_name: 'Kim Driver',
          driver_phone: '010',
          vehicle_type_id: 1,
          vehicle_type_code: 'SEDAN',
          vehicle_type_name: 'Sedan',
          plate_number: 'OK-1',
          model_name: 'Camry',
          color: 'White',
          is_primary: 1,
          is_active: 1,
          approval_status: 'APPROVED',
          rejection_reason: null,
          created_at: '2026-07-01T00:00:00.000Z',
          updated_at: '2026-07-01T00:00:00.000Z',
          files_json: '[]',
        },
      ];
      const filtered = filters.status
        ? all.filter((row) => row.approval_status === filters.status)
        : all;
      return { items: filtered, total: filtered.length };
    },
    async findVehicleByIdForUpdate(_conn, id) {
      if (Number(id) !== Number(pendingRow.id)) return null;
      return { ...pendingRow };
    },
    async approveVehicle(_conn, vehicleId, actorUserId) {
      calls.approve.push({ vehicleId, actorUserId });
    },
    async rejectVehicle(_conn, vehicleId, payload) {
      calls.reject.push({ vehicleId, ...payload });
    },
    async insertVehicleAuditLog(_conn, payload) {
      calls.audits.push(payload);
    },
  };

  const service = new DriverVehicleService(
    pool,
    driverRepository,
    {},
    {},
  );
  return { service, conn, calls, pendingRow };
}

test('listAdmin filters PENDING vehicles and includes file URLs', async () => {
  const { service, calls } = createAdminHarness();
  const result = await service.listAdmin({ status: 'PENDING' });
  assert.equal(calls.listFilters[0].filters.status, 'PENDING');
  assert.equal(result.total, 1);
  assert.equal(result.items.length, 1);
  assert.equal(result.items[0].approvalStatus, 'PENDING');
  assert.equal(result.items[0].driverName, 'Kim Driver');
  assert.equal(result.items[0].files[0].url, '/api/v1/admin/driver-vehicles/55/files/901');
});

test('approve sets APPROVED active vehicle and writes audit log', async () => {
  const { service, conn, calls } = createAdminHarness();
  const result = await service.approve(55, { adminNote: 'ok' }, { id: 9 }, {
    ipAddress: '127.0.0.1',
  });
  assert.equal(conn.committed, true);
  assert.equal(calls.approve.length, 1);
  assert.equal(calls.approve[0].vehicleId, 55);
  assert.equal(result.approvalStatus, 'APPROVED');
  assert.equal(result.isActive, true);
  assert.equal(calls.audits[0].action, 'driver_vehicle.approved');
  assert.equal(calls.audits[0].entityId, 55);
});

test('reject stores rejection reason and keeps inactive', async () => {
  const { service, calls } = createAdminHarness();
  const result = await service.reject(
    55,
    { rejectionReason: '서류 미비' },
    { id: 9 },
    { ipAddress: '127.0.0.1' },
  );
  assert.equal(calls.reject[0].rejectionReason, '서류 미비');
  assert.equal(result.approvalStatus, 'REJECTED');
  assert.equal(result.isActive, false);
  assert.equal(result.rejectionReason, '서류 미비');
  assert.equal(calls.audits[0].action, 'driver_vehicle.rejected');
});

test('DRIVER cannot call admin vehicle approve API (403)', async () => {
  const res = await request(app)
    .post('/api/v1/admin/driver-vehicles/55/approve')
    .set('Authorization', `Bearer ${sign('DRIVER', 42)}`)
    .send({});
  assert.equal(res.status, 403);
  assert.equal(res.body.error_code, ERROR_CODES.FORBIDDEN);
});

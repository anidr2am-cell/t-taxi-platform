const test = require('node:test');
const assert = require('node:assert/strict');
const { driverInsurance, validInsuranceDate } = require('../src/utils/driverInsurance.util');
const { files, updateInsurance } = require('../src/services/adminDriverVehicleMedia.service');

test('insurance uses a calendar month warning, clamps month ends and honors Bangkok dates', () => {
  assert.equal(driverInsurance('2027-03-31', new Date('2027-02-27T16:59:59Z')).status, 'VALID');
  assert.equal(driverInsurance('2027-03-31', new Date('2027-02-27T17:00:00Z')).status, 'EXPIRING');
  assert.equal(driverInsurance('2028-03-31', new Date('2028-02-28T17:00:00Z')).status, 'EXPIRING');
  assert.equal(driverInsurance('2027-01-15', new Date('2026-12-14T17:00:00Z')).status, 'EXPIRING');
  assert.equal(driverInsurance('2026-11-19', new Date('2026-11-19T16:59:59Z')).status, 'EXPIRING');
  assert.equal(driverInsurance('2026-11-19', new Date('2026-11-19T17:00:00Z')).status, 'EXPIRED');
  assert.equal(driverInsurance(null).status, 'MISSING');
  assert.equal(validInsuranceDate('2026-02-29'), false);
});

test('missing legacy files remain visible as unavailable and do not hide valid photos', async () => {
  const db = { async query(sql, params) {
    assert.deepEqual(params, [3, 6, null, null]);
    assert.match(sql, /v\.driver_id=\?/);
    assert.match(sql, /av\.plate_number=da\.vehicle_plate_number/);
    return [[
      { id: 1, file_path: 'qa/missing.jpg', category: 'DRIVER_VEHICLE_PHOTO', mime_type: 'image/jpeg' },
      { id: 2, file_path: 'qa/valid.png', category: 'DRIVER_VEHICLE_PHOTO', mime_type: 'image/png' },
    ]];
  } };
  const storage = {
    async stat(path) { if (path.endsWith('missing.jpg')) throw new Error('missing'); return { isFile: () => true }; },
    async access() {},
  };
  const rows = await files(6, 3, null, db, storage);
  assert.deepEqual(rows.map(r => r.available), [false, true]);
  assert.ok(rows.every(r => !('file_path' in r)));
});

test('unrelated or missing vehicle files return 404', async () => {
  await assert.rejects(files(6, 3, 99, { query: async () => [[]] }), { statusCode: 404 });
});

test('insurance edits audit old and new dates in the same transaction', async () => {
  const events = [];
  const conn = {
    beginTransaction: async () => events.push('begin'),
    commit: async () => events.push('commit'),
    rollback: async () => events.push('rollback'),
    release: () => events.push('release'),
    async query(sql, params) {
      if (sql.includes('SELECT DATE_FORMAT')) return [[{ previousDate: null }]];
      if (sql.includes('INSERT INTO audit_logs')) {
        assert.deepEqual(params.slice(0, 2), [1, 3]);
        assert.deepEqual(JSON.parse(params[2]), { driverId: 6, previousDate: null, expiresOn: '2027-05-01' });
      }
      return [{ affectedRows: 1 }];
    },
  };
  const result = await updateInsurance(6, 3, '2027-05-01', { id: 1 }, { getConnection: async () => conn });
  assert.equal(result.expiresOn, '2027-05-01');
  assert.deepEqual(events, ['begin', 'commit', 'release']);
  await assert.rejects(updateInsurance(6, 3, '2026-02-30', { id: 1 }), { errorCode: 'VALIDATION_ERROR' });
});

test('vehicle belonging to another driver cannot be edited', async () => {
  const events = [];
  const db = { getConnection: async () => ({
    beginTransaction: async () => {}, query: async () => [[]],
    commit: async () => events.push('commit'), rollback: async () => events.push('rollback'),
    release: () => events.push('release'),
  }) };
  await assert.rejects(updateInsurance(6, 99, '2027-05-01', { id: 1 }, db), { statusCode: 404 });
  assert.deepEqual(events, ['rollback', 'release']);
});

test('media and insurance routes require administrator authentication', async () => {
  const request = require('supertest');
  const jwt = require('jsonwebtoken');
  const app = require('../src/app');
  const driver = jwt.sign({ sub: 6, role: 'DRIVER', type: 'access' }, process.env.JWT_ACCESS_SECRET, { expiresIn: '1h' });
  for (const [method, path] of [
    ['get', '/api/v1/admin/drivers/6/vehicles/3/media'],
    ['get', '/api/v1/admin/drivers/6/vehicles/3/media/8'],
    ['patch', '/api/v1/admin/drivers/6/vehicles/3/insurance'],
  ]) {
    assert.equal((await request(app)[method](path)).status, 401);
    assert.equal((await request(app)[method](path).set('Authorization', 'Bearer ' + driver)).status, 403);
  }
});

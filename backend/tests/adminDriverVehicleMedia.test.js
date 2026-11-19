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

test('MariaDB migration round-trip and vehicle-bound registration media', {
  skip: !process.env.GUEST_LOOKUP_TEST_DB,
}, async () => {
  assert.match(process.env.GUEST_LOOKUP_TEST_DB, /^qa_guest_lookup_[a-z0-9_]+$/);
  const database = 'qa_guest_lookup_driver_media_' + require('node:crypto').randomBytes(6).toString('hex');
  const mysql = require('mysql2/promise');
  const connection = await mysql.createConnection({
    host: process.env.GUEST_LOOKUP_TEST_DB_HOST || '127.0.0.1',
    port: Number(process.env.GUEST_LOOKUP_TEST_DB_PORT || 33317),
    user: process.env.GUEST_LOOKUP_TEST_DB_USER || 'root',
    password: process.env.GUEST_LOOKUP_TEST_DB_PASSWORD || '',
    database: process.env.GUEST_LOOKUP_TEST_DB,
  });
  let created = false;
  try {
    await connection.query('CREATE DATABASE ' + database + ' CHARACTER SET utf8mb4');
    created = true;
    await connection.changeUser({ database });
    for (const sql of [
      'CREATE TABLE drivers (id INT PRIMARY KEY, deleted_at DATETIME)',
      'CREATE TABLE driver_vehicles (id INT PRIMARY KEY,driver_id INT,plate_number VARCHAR(30),deleted_at DATETIME,updated_at DATETIME)',
      'CREATE TABLE driver_vehicle_files (driver_vehicle_id INT,file_id INT,category VARCHAR(60))',
      'CREATE TABLE driver_applications (id INT PRIMARY KEY,approved_driver_id INT,vehicle_plate_number VARCHAR(30),status VARCHAR(30),deleted_at DATETIME)',
      'CREATE TABLE driver_application_files (driver_application_id INT,file_id INT,category VARCHAR(60))',
      'CREATE TABLE files (id INT PRIMARY KEY,file_path VARCHAR(100),mime_type VARCHAR(60),deleted_at DATETIME)',
      'CREATE TABLE audit_logs (user_id INT,action VARCHAR(60),entity_type VARCHAR(30),entity_id INT,payload JSON)',
      'INSERT INTO drivers VALUES(6,NULL),(7,NULL)',
      "INSERT INTO driver_vehicles VALUES(3,6,'QA123',NULL,NULL),(4,7,'QA999',NULL,NULL)",
      "INSERT INTO driver_applications VALUES(1,6,'QA123','APPROVED',NULL),(2,7,'QA999','APPROVED',NULL)",
      "INSERT INTO driver_application_files VALUES(1,11,'DRIVER_VEHICLE_PHOTO'),(2,99,'DRIVER_VEHICLE_PHOTO')",
      "INSERT INTO driver_vehicle_files VALUES(3,12,'DRIVER_INSURANCE_CERTIFICATE')",
      "INSERT INTO files VALUES(11,'qa/photo.png','image/png',NULL),(12,'qa/insurance.pdf','application/pdf',NULL),(99,'qa/other.png','image/png',NULL)",
    ]) await connection.query(sql);
    const path = require('node:path');
    const fs = require('node:fs');
    const apply = fs.readFileSync(path.resolve(__dirname, '../../database/79_driver_vehicle_insurance.sql'), 'utf8');
    const rollback = fs.readFileSync(path.resolve(__dirname, '../../database/rollback_79_driver_vehicle_insurance.sql'), 'utf8');
    await connection.query(apply);
    const db = { query: (...args) => connection.query(...args), getConnection: async () => ({
      query: (...args) => connection.query(...args),
      beginTransaction: () => connection.beginTransaction(),
      commit: () => connection.commit(), rollback: () => connection.rollback(), release() {},
    }) };
    const storage = { stat: async () => ({ isFile: () => true }), access: async () => {} };
    const media = await files(6, 3, null, db, storage);
    assert.deepEqual(media.map(r => r.fileId), [12, 11]);
    await assert.rejects(files(6, 3, 99, db, storage), { statusCode: 404 });
    await updateInsurance(6, 3, '2027-05-01', { id: 1 }, db);
    const [[saved]] = await connection.query("SELECT DATE_FORMAT(insurance_expires_on,'%Y-%m-%d') AS expiresOn FROM driver_vehicles WHERE id=3");
    assert.equal(saved.expiresOn, '2027-05-01');
    const [[audit]] = await connection.query('SELECT COUNT(*) AS count FROM audit_logs');
    assert.equal(audit.count, 1);
    await connection.query(rollback);
    await assert.rejects(connection.query('SELECT insurance_expires_on FROM driver_vehicles'), { code: 'ER_BAD_FIELD_ERROR' });
    await connection.query(apply);
    const [[reset]] = await connection.query('SELECT insurance_expires_on FROM driver_vehicles WHERE id=3');
    assert.equal(reset.insurance_expires_on, null);
  } finally {
    if (created) await connection.query('DROP DATABASE ' + database);
    await connection.end();
  }
});

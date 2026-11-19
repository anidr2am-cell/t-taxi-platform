const test = require('node:test');
const assert = require('node:assert/strict');
const { deleteDriver } = require('../src/services/adminDriverDeletion.service');

function fixture({ blocking = [], deleted = false, failAudit = false } = {}) {
  const operations = [];
  const conn = {
    async beginTransaction() { operations.push('begin'); },
    async commit() { operations.push('commit'); },
    async rollback() { operations.push('rollback'); },
    release() { operations.push('release'); },
    async query(sql, params) {
      operations.push(sql);
      if (sql.startsWith('SELECT id, user_id')) return [[{ id: 2, user_id: 20, deleted_at: deleted ? '2026-01-01' : null }]];
      if (sql.startsWith('SELECT id, role')) return [[{ id: 20, role: 'DRIVER' }]];
      if (sql.includes('SELECT b.booking_number')) return [blocking.map(booking_number => ({ booking_number }))];
      if (sql.includes('INSERT INTO audit_logs')) {
        if (failAudit) throw new Error('audit unavailable');
        assert.deepEqual(params.slice(0, 2), [1, 2]);
        assert.deepEqual(JSON.parse(params[2]), { reason: 'QA deletion', driverId: 2, userId: 20 });
      }
      return [{ affectedRows: 1 }];
    },
  };
  return { pool: { getConnection: async () => conn }, operations };
}

test('soft deletion disables account, invalidates refresh and records audit atomically', async () => {
  const { pool, operations } = fixture();
  assert.deepEqual(await deleteDriver(pool, 2, 'QA deletion', { id: 1 }), { driverId: 2, deleted: true });
  assert.ok(operations.some(s => s.includes('UPDATE drivers SET deleted_at')));
  assert.ok(operations.some(s => s.includes('auth_token_version=auth_token_version+1')));
  assert.equal(operations.filter(s => /DELETE FROM/i.test(s)).length, 0);
  assert.deepEqual(operations.slice(-2), ['commit', 'release']);
});

test('active assignments or unpaid settlement block deletion and report booking numbers', async () => {
  const { pool, operations } = fixture({ blocking: ['TX209901010001'] });
  await assert.rejects(deleteDriver(pool, 2, 'QA deletion', { id: 1 }), e => {
    assert.equal(e.statusCode, 409);
    assert.deepEqual(e.details.bookingNumbers, ['TX209901010001']);
    return true;
  });
  assert.equal(operations.some(s => s.startsWith('UPDATE')), false);
  assert.deepEqual(operations.slice(-2), ['rollback', 'release']);
});

test('audit failure rolls back deletion', async () => {
  const { pool, operations } = fixture({ failAudit: true });
  await assert.rejects(deleteDriver(pool, 2, 'QA deletion', { id: 1 }), /audit unavailable/);
  assert.equal(operations.includes('commit'), false);
  assert.deepEqual(operations.slice(-2), ['rollback', 'release']);
});

test('already deleted drivers return not found without account changes', async () => {
  const { pool, operations } = fixture({ deleted: true });
  await assert.rejects(deleteDriver(pool, 2, 'QA deletion', { id: 1 }), { errorCode: 'DRIVER_NOT_FOUND' });
  assert.equal(operations.some(s => s.startsWith('UPDATE')), false);
});

test('MariaDB deletion preserves settled bookings and blocks newly assigned work', {
  skip: !process.env.GUEST_LOOKUP_TEST_DB,
}, async () => {
  assert.match(process.env.GUEST_LOOKUP_TEST_DB, /^qa_guest_lookup_[a-z0-9_]+$/);
  const connection = await require('mysql2/promise').createConnection({
    host: process.env.GUEST_LOOKUP_TEST_DB_HOST || '127.0.0.1',
    port: Number(process.env.GUEST_LOOKUP_TEST_DB_PORT || 33317),
    user: process.env.GUEST_LOOKUP_TEST_DB_USER || 'root',
    password: process.env.GUEST_LOOKUP_TEST_DB_PASSWORD || '',
    database: process.env.GUEST_LOOKUP_TEST_DB,
  });
  const pool = { getConnection: async () => ({
    query: (...args) => connection.query(...args),
    beginTransaction: () => connection.beginTransaction(),
    commit: () => connection.commit(),
    rollback: () => connection.rollback(),
    release() {},
  }) };
  try {
    for (const sql of [
      'CREATE TEMPORARY TABLE drivers (id INT PRIMARY KEY,user_id INT,deleted_at DATETIME,is_online INT,updated_at DATETIME) ENGINE=InnoDB',
      'CREATE TEMPORARY TABLE users (id INT PRIMARY KEY,role VARCHAR(30),is_active INT,auth_token_version INT,updated_at DATETIME) ENGINE=InnoDB',
      'CREATE TEMPORARY TABLE bookings (id INT PRIMARY KEY,booking_number VARCHAR(30),driver_id INT,status VARCHAR(30),commission_status VARCHAR(30),deleted_at DATETIME) ENGINE=InnoDB',
      'CREATE TEMPORARY TABLE booking_driver_assignments (booking_id INT,driver_id INT,is_active INT,deleted_at DATETIME) ENGINE=InnoDB',
      'CREATE TEMPORARY TABLE audit_logs (user_id INT,action VARCHAR(50),entity_type VARCHAR(30),entity_id INT,payload JSON) ENGINE=InnoDB',
      'INSERT INTO drivers VALUES (2,20,NULL,1,NULL), (6,60,NULL,0,NULL)',
      "INSERT INTO users VALUES (20,'DRIVER',1,0,NULL),(60,'DRIVER',1,0,NULL)",
      "INSERT INTO bookings VALUES (1,'TX209901010001',2,'COMPLETED','PAID',NULL),(2,'TX209901010002',6,'DRIVER_ASSIGNED','NOT_DUE_YET',NULL)",
      'INSERT INTO booking_driver_assignments VALUES (2,6,1,NULL)',
    ]) await connection.query(sql);
    await deleteDriver(pool, 2, 'QA deletion', { id: 1 });
    const [[driver]] = await connection.query('SELECT deleted_at,is_online FROM drivers WHERE id=2');
    assert.ok(driver.deleted_at);
    assert.equal(driver.is_online, 0);
    const [[user]] = await connection.query('SELECT is_active,auth_token_version FROM users WHERE id=20');
    assert.deepEqual(user, { is_active: 0, auth_token_version: 1 });
    const [[history]] = await connection.query('SELECT COUNT(*) AS count FROM bookings WHERE driver_id=2');
    assert.equal(history.count, 1);
    await assert.rejects(deleteDriver(pool, 6, 'QA deletion', { id: 1 }), { errorCode: 'DRIVER_DELETE_BLOCKED' });
    const [[blockedDriver]] = await connection.query('SELECT deleted_at FROM drivers WHERE id=6');
    assert.equal(blockedDriver.deleted_at, null);
    const [[audit]] = await connection.query('SELECT COUNT(*) AS count FROM audit_logs');
    assert.equal(audit.count, 1);
  } finally {
    await connection.end();
  }
});

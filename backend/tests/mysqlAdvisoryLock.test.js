const test = require('node:test');
const assert = require('node:assert/strict');

const {
  acquireNamedLock,
  releaseNamedLock,
  contactDispatchLockName,
} = require('../src/utils/mysqlAdvisoryLock');
const { createLockState } = require('./support/mysqlAdvisoryLock.helpers');

test('contactDispatchLockName is stable per booking id', () => {
  assert.equal(contactDispatchLockName(42), 'tride:contact-dispatch:42');
});

test('acquireNamedLock and releaseNamedLock use the same connection', async () => {
  const lockState = createLockState();
  const conn = lockState.createConn();

  assert.equal(await acquireNamedLock(conn, 'tride:contact-dispatch:1', 1), true);
  assert.equal(lockState.held.has('tride:contact-dispatch:1'), true);
  assert.equal(await releaseNamedLock(conn, 'tride:contact-dispatch:1'), true);
  assert.equal(lockState.held.has('tride:contact-dispatch:1'), false);
});

test('acquireNamedLock returns false when lock is already held', async () => {
  const lockState = createLockState();
  const connA = lockState.createConn();
  const connB = lockState.createConn();

  assert.equal(await acquireNamedLock(connA, 'tride:contact-dispatch:9', 0), true);
  assert.equal(await acquireNamedLock(connB, 'tride:contact-dispatch:9', 0), false);
  assert.equal(await releaseNamedLock(connA, 'tride:contact-dispatch:9'), true);
});

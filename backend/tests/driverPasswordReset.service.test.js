const test = require('node:test');
const assert = require('node:assert/strict');
const bcrypt = require('bcryptjs');

const DriverPasswordResetService = require('../src/services/driverPasswordReset.service');
const ERROR_CODES = require('../src/constants/errorCodes');

function harness({ user = { id: 10, email: 'driver@example.com', phone: '0812345678', role: 'DRIVER', is_active: 1, locale: 'ko' } } = {}) {
  const state = { created: null, consumed: null, email: null };
  const users = {
    findByEmail: async (email) => email === user?.email ? user : null,
    findDriverByPhone: async (phone) => phone === user?.phone ? user : null,
  };
  const resets = {
    createCode: async (value) => { state.created = value; },
    consumeCodeAndUpdatePassword: async (value) => { state.consumed = value; return value.codeHash === state.created?.codeHash; },
  };
  const email = { sendCode: async (value) => { state.email = value; } };
  const service = new DriverPasswordResetService(users, resets, email, {
    now: () => Date.parse('2026-10-02T00:00:00Z'),
    randomInt: () => 123456,
    secret: 'test-reset-secret',
  });
  return { service, state };
}

test('requestCode sends a six digit code to the registered driver email and stores only a hash', async () => {
  const { service, state } = harness();
  await service.requestCode('0812345678');
  assert.equal(state.email.email, 'driver@example.com');
  assert.equal(state.email.code, '123456');
  assert.equal(state.created.userId, 10);
  assert.notEqual(state.created.codeHash, '123456');
  assert.equal(state.created.expiresAt.toISOString(), '2026-10-02T00:10:00.000Z');
});

test('requestCode returns the same public behavior for an unknown account', async () => {
  const { service, state } = harness({ user: null });
  await assert.doesNotReject(service.requestCode('unknown@example.com'));
  assert.equal(state.created, null);
  assert.equal(state.email, null);
});

test('resetPassword accepts the valid code and hashes the new password', async () => {
  const { service, state } = harness();
  await service.requestCode('driver@example.com');
  await service.resetPassword({ identifier: 'driver@example.com', code: '123456', newPassword: 'NewPassword123!' });
  assert.equal(state.consumed.userId, 10);
  assert.equal(state.consumed.maxAttempts, 5);
  assert.equal(await bcrypt.compare('NewPassword123!', state.consumed.passwordHash), true);
});

test('resetPassword rejects an invalid code without revealing account details', async () => {
  const { service } = harness();
  await service.requestCode('0812345678');
  await assert.rejects(
    service.resetPassword({ identifier: '0812345678', code: '654321', newPassword: 'NewPassword123!' }),
    (err) => err.errorCode === ERROR_CODES.PASSWORD_RESET_CODE_INVALID,
  );
});

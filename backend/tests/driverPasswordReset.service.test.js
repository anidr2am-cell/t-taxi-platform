const test = require('node:test');
const assert = require('node:assert/strict');
const bcrypt = require('bcryptjs');

const DriverPasswordResetService = require('../src/services/driverPasswordReset.service');
const ERROR_CODES = require('../src/constants/errorCodes');

function harness({ user = { id: 10, email: 'driver@example.com', phone: '0812345678', role: 'DRIVER', is_active: 1, locale: 'ko' } } = {}) {
  const state = { created: null, consumed: null, email: null, changed: null };
  const users = {
    findById: async (id) => id === user?.id ? user : null,
    findByEmail: async (email) => email === user?.email ? user : null,
    findDriverByPhone: async (phone) => phone === user?.phone ? user : null,
    findUniqueDriverForReset: async (phones) => phones.includes(user?.phone) ? user : null,
  };
  const resets = {
    createCode: async (value) => { state.created = value; },
    consumeCodeAndUpdatePassword: async (value) => { state.consumed = value; return value.codeHash === state.created?.codeHash; },
    changePassword: async (value) => {
      state.changed = value;
      return !state.simulateConcurrentChange;
    },
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

test('Thai mobile aliases resolve to the same account for request and confirmation', async () => {
  const user = { id: 10, email: 'driver@example.com', phone: '+66812345678', role: 'DRIVER', is_active: 1 };
  const { service, state } = harness({ user });
  await service.requestCode('081-234-5678');
  await service.resetPassword({ identifier: '0066812345678', code: '123456', newPassword: 'NewPassword123!' });
  assert.equal(state.created.userId, 10);
  assert.equal(state.consumed.userId, 10);
});

test('placeholder and missing emails do not create a code or send mail', async () => {
  for (const email of ['driver+1@driver.local', null]) {
    const { service, state } = harness({ user: { id: 10, email, phone: '0812345678', role: 'DRIVER', is_active: 1 } });
    await service.requestCode('+66812345678');
    assert.equal(state.created, null);
    assert.equal(state.email, null);
  }
});

test('phone aliases share a single reset rate-limit identifier', () => {
  const { normalizeDriverResetIdentifier } = require('../src/utils/driverResetIdentifier.util');
  for (const value of ['0812345678', '+66 81 234 5678', '0066812345678', '66812345678']) {
    assert.equal(normalizeDriverResetIdentifier(value), '+66812345678');
  }
  assert.equal(normalizeDriverResetIdentifier(' DRIVER@example.com '), 'driver@example.com');
});

test('two driver accounts with equivalent numbers are not selected by phone', async () => {
  const UserRepository = require('../src/repositories/user.repository');
  const repository = new UserRepository({
    async query(sql, params) {
      assert.match(sql, /REGEXP_REPLACE\(phone, '\[ \(\)-\]', ''\) IN \(\?\)/);
      assert.deepEqual(params, [
        ['0812345678', '+66812345678'], ['0812345678', '+66812345678'],
      ]);
      return [[{ id: 10 }, { id: 11 }]];
    },
  });
  assert.equal(await repository.findUniqueDriverForReset(['0812345678', '+66812345678']), null);
});

test('changePassword verifies the current driver password and writes only hashes', async () => {
  const passwordHash = await bcrypt.hash('current-test-password', 4);
  const user = { id: 10, role: 'DRIVER', is_active: 1, password_hash: passwordHash };
  const { service, state } = harness({ user });
  await assert.rejects(
    service.changePassword(10, 'incorrect-password', 'new-test-password'),
    { errorCode: ERROR_CODES.CURRENT_PASSWORD_INCORRECT },
  );
  await assert.rejects(
    service.changePassword(10, 'current-test-password', 'current-test-password'),
    { errorCode: ERROR_CODES.PASSWORD_UNCHANGED },
  );
  assert.equal(state.changed, null);

  await service.changePassword(10, 'current-test-password', 'new-test-password');
  assert.equal(state.changed.userId, 10);
  assert.equal(state.changed.currentHash, passwordHash);
  assert.equal(await bcrypt.compare('new-test-password', state.changed.passwordHash), true);
  assert.equal(state.email, null);
});

test('changePassword rejects inactive or non-driver accounts and stale writes', async () => {
  const passwordHash = await bcrypt.hash('current-test-password', 4);
  const user = { id: 10, role: 'DRIVER', is_active: 1, password_hash: passwordHash };
  const { service, state } = harness({ user });
  for (const override of [{ is_active: 0 }, { role: 'CUSTOMER' }]) {
    const disabled = harness({ user: { ...user, ...override } });
    await assert.rejects(
      disabled.service.changePassword(10, 'current-test-password', 'new-test-password'),
      { errorCode: ERROR_CODES.CURRENT_PASSWORD_INCORRECT },
    );
    assert.equal(disabled.state.changed, null);
  }
  state.simulateConcurrentChange = true;
  await assert.rejects(
    service.changePassword(10, 'current-test-password', 'new-test-password'),
    { errorCode: ERROR_CODES.PASSWORD_CHANGE_CONFLICT },
  );
});

test('changePassword transaction invalidates reset codes and preserves a newer password', async () => {
  const DriverPasswordResetRepository = require('../src/repositories/driverPasswordReset.repository');
  for (const affectedRows of [1, 0]) {
    const steps = [];
    const conn = {
      async beginTransaction() { steps.push('begin'); },
      async query(sql, params) {
        assert.match(sql, /UPDATE driver_password_reset_codes/);
        steps.push('invalidate codes');
        assert.deepEqual(params, [10]);
        return [{}];
      },
      async execute(sql, params) {
        steps.push('update password');
        assert.match(sql, /auth_token_version = auth_token_version \+ 1/);
        assert.match(sql, /CAST\(password_hash AS BINARY\) = CAST\(\? AS BINARY\)/);
        assert.deepEqual(params, ['new-test-hash', 10, 'current-test-hash']);
        return [{ affectedRows }];
      },
      async commit() { steps.push('commit'); },
      async rollback() { steps.push('rollback'); },
      release() { steps.push('release'); },
    };
    const repository = new DriverPasswordResetRepository({ getConnection: async () => conn });
    assert.equal(await repository.changePassword({
      userId: 10,
      currentHash: 'current-test-hash',
      passwordHash: 'new-test-hash',
    }), affectedRows === 1);
    assert.deepEqual(steps, [
      'begin', 'invalidate codes', 'update password', affectedRows === 1 ? 'commit' : 'rollback', 'release',
    ]);
  }
});

test('driver password change route uses the authenticated account and validates the UTF-8 length', async (t) => {
  const request = require('supertest');
  const jwt = require('jsonwebtoken');
  const app = require('../src/app');
  const container = require('../src/helpers/container');
  const service = container.get('driverPasswordResetService');
  const changePassword = t.mock.method(service, 'changePassword', async () => {});
  const token = (role) => jwt.sign(
    { sub: 10, type: 'access', role },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '5m' },
  );
  const endpoint = '/api/v1/driver/profile/password';
  const body = { currentPassword: 'current-test-password', newPassword: 'new-test-password' };

  await request(app).post(endpoint).send(body).expect(401);
  await request(app).post(endpoint).set('Authorization', `Bearer ${token('CUSTOMER')}`).send(body).expect(403);
  const authorized = () => request(app).post(endpoint).set('Authorization', `Bearer ${token('DRIVER')}`);
  await authorized().send({ ...body, newPassword: 'ก'.repeat(25) }).expect(400);
  const allowed = { ...body, newPassword: 'ก'.repeat(24), userId: 20 };
  const response = await authorized().send(allowed).expect(200);
  assert.equal(response.body.data, null);
  assert.equal(changePassword.mock.callCount(), 1);
  assert.deepEqual(changePassword.mock.calls[0].arguments, [10, body.currentPassword, allowed.newPassword]);
});

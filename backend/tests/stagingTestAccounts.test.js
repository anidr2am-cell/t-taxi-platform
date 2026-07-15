const test = require('node:test');
const assert = require('node:assert/strict');

const ROLES = require('../src/constants/roles');
const provision = require('../scripts/provision-staging-test-accounts');
const runner = require('../scripts/staging-booking-regression');

function withEnv(values, fn) {
  const previous = {};
  for (const key of Object.keys(values)) {
    previous[key] = process.env[key];
    if (values[key] === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = values[key];
    }
  }
  try {
    return fn();
  } finally {
    for (const key of Object.keys(values)) {
      if (previous[key] === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = previous[key];
      }
    }
  }
}

function strongPassword(suffix) {
  return `E2e-${suffix}-Password-2026!`;
}

function fakeDryRunPool() {
  const calls = [];
  const conn = {
    calls,
    async beginTransaction() {
      calls.push(['begin']);
    },
    async rollback() {
      calls.push(['rollback']);
    },
    async commit() {
      calls.push(['commit']);
    },
    release() {
      calls.push(['release']);
    },
    async query(sql, params = []) {
      calls.push(['query', sql, params]);
      if (/SELECT DATABASE\(\) AS name/.test(sql)) {
        return [[{ name: 'ttaxi_staging' }]];
      }
      if (/information_schema\.TABLES/.test(sql)) {
        return [[
          { TABLE_NAME: 'users' },
          { TABLE_NAME: 'user_profiles' },
          { TABLE_NAME: 'drivers' },
          { TABLE_NAME: 'driver_vehicles' },
          { TABLE_NAME: 'vehicle_types' },
        ]];
      }
      if (/FROM vehicle_types/.test(sql)) {
        return [[{ id: 2, code: 'SUV' }]];
      }
      throw new Error(`Unexpected query in dry-run: ${sql}`);
    },
  };
  return {
    conn,
    async getConnection() {
      return conn;
    },
  };
}

test('provision config requires explicit live opt-in and strong distinct passwords', () => {
  withEnv({
    TRIDE_PROVISION_TEST_ACCOUNTS: undefined,
    TRIDE_TEST_ADMIN_PASSWORD: strongPassword('Admin'),
    TRIDE_TEST_DRIVER_PASSWORD: strongPassword('Driver'),
  }, () => {
    assert.throws(
      () => provision.resolveConfig({ dryRun: false }),
      /TRIDE_PROVISION_TEST_ACCOUNTS=1/,
    );
  });

  withEnv({
    TRIDE_PROVISION_TEST_ACCOUNTS: '1',
    TRIDE_TEST_ADMIN_PASSWORD: 'short',
    TRIDE_TEST_DRIVER_PASSWORD: strongPassword('Driver'),
  }, () => {
    assert.throws(
      () => provision.resolveConfig({ dryRun: false }),
      /TRIDE_TEST_ADMIN_PASSWORD/,
    );
  });

  withEnv({
    TRIDE_PROVISION_TEST_ACCOUNTS: '1',
    TRIDE_TEST_ADMIN_PASSWORD: strongPassword('Shared'),
    TRIDE_TEST_DRIVER_PASSWORD: strongPassword('Shared'),
  }, () => {
    assert.throws(
      () => provision.resolveConfig({ dryRun: false }),
      /must differ/,
    );
  });
});

test('provision dry-run validates T-Ride schema and performs no writes', async () => {
  const pool = fakeDryRunPool();
  const result = await withEnv({
    TRIDE_TEST_ADMIN_PASSWORD: undefined,
    TRIDE_TEST_DRIVER_PASSWORD: undefined,
  }, () => provision.provisionAccounts(pool, provision.resolveConfig({ dryRun: true })));

  assert.equal(result.dryRun, true);
  assert.equal(result.databaseName, 'ttaxi_staging');
  assert.equal(result.admin.email, provision.DEFAULT_ADMIN_EMAIL);
  assert.equal(result.admin.role, ROLES.ADMIN);
  assert.equal(result.driver.email, provision.DEFAULT_DRIVER_EMAIL);
  assert.equal(result.driver.vehicleTypeCode, 'SUV');
  assert.equal(pool.conn.calls.some(([kind]) => kind === 'commit'), false);
  assert.equal(pool.conn.calls.some(([kind, sql]) => kind === 'query' && /\bINSERT\b|\bUPDATE\b/.test(sql)), false);
});

test('provision refuses existing non-test accounts', () => {
  assert.throws(
    () => provision.assertExistingUserIsTestAccount({
      email: 'admin@example.com',
      display_name: 'Operations Admin',
    }, 'Admin'),
    /non-test account/,
  );

  assert.doesNotThrow(() => provision.assertExistingUserIsTestAccount({
    email: 'tride.e2e.admin@invalid.example',
    display_name: '[E2E] Regression Admin',
  }, 'Admin'));
});

test('booking regression runner refuses non-test identities and selects only matching test driver', () => {
  assert.equal(
    runner.isTestIdentity(
      { email: 'tride.e2e.driver@invalid.example', role: 'DRIVER', name: '[E2E] Regression Driver' },
      'tride.e2e.driver@invalid.example',
      'DRIVER',
    ),
    true,
  );
  assert.equal(
    runner.isTestIdentity(
      { email: 'driver@real.example', role: 'DRIVER', name: 'Real Driver' },
      'driver@real.example',
      'DRIVER',
    ),
    false,
  );

  const candidate = runner.selectTestDriverCandidate({
    data: {
      candidates: [
        { driverId: 1, displayName: 'Real Driver', eligible: true },
        { driverId: 2, displayName: '[E2E] Regression Driver', eligible: true },
      ],
    },
  }, { name: '[E2E] Regression Driver' });
  assert.equal(candidate.driverId, 2);

  assert.throws(
    () => runner.selectTestDriverCandidate({
      data: { candidates: [{ driverId: 1, displayName: 'Real Driver', eligible: true }] },
    }, { name: '[E2E] Regression Driver' }),
    /Expected test driver/,
  );
});

test('booking regression runner validates live email env before login', () => {
  withEnv({
    TRIDE_BASE_URL: 'https://trider.taxi',
    TRIDE_ADMIN_EMAIL: 'not-an-email',
    TRIDE_ADMIN_PASSWORD: 'secret',
    TRIDE_TEST_DRIVER_EMAIL: 'tride.e2e.driver@invalid.example',
    TRIDE_TEST_DRIVER_PASSWORD: 'secret',
    TRIDE_ALLOW_LIVE_BOOKING_REGRESSION: '1',
  }, () => {
    assert.throws(
      () => runner.assertSafeEnvironment({ dryRun: false }),
      /TRIDE_ADMIN_EMAIL must be a valid email/,
    );
  });

  withEnv({
    TRIDE_BASE_URL: 'https://trider.taxi',
    TRIDE_TEST_ADMIN_EMAIL: 'tride.e2e.admin@invalid.example',
    TRIDE_ADMIN_EMAIL: 'other.admin@invalid.example',
    TRIDE_ADMIN_PASSWORD: 'secret',
    TRIDE_TEST_DRIVER_EMAIL: 'tride.e2e.driver@invalid.example',
    TRIDE_TEST_DRIVER_PASSWORD: 'secret',
    TRIDE_ALLOW_LIVE_BOOKING_REGRESSION: '1',
  }, () => {
    assert.throws(
      () => runner.assertSafeEnvironment({ dryRun: false }),
      /TRIDE_ADMIN_EMAIL must match TRIDE_TEST_ADMIN_EMAIL/,
    );
  });
});

test('booking regression runner formats validation details without request body', () => {
  const message = runner.formatHttpError(
    '/api/v1/auth/login',
    400,
    {
      error_code: 'VALIDATION_ERROR',
      message: 'Validation failed',
      errors: [{ field: 'email', type: 'string.email', source: 'body' }],
    },
    'VALIDATION_ERROR',
  );

  assert.match(message, /HTTP 400 VALIDATION_ERROR/);
  assert.match(message, /email:string.email:body/);
  assert.equal(message.includes('password'), false);
});

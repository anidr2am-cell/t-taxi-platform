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

function fakeProvisionPool(seed, options = {}) {
  const state = {
    users: seed.users.map((row) => ({ ...row })),
    drivers: seed.drivers.map((row) => ({ ...row })),
    vehicles: seed.vehicles.map((row) => ({ ...row })),
  };
  let snapshot = null;
  const calls = [];
  const conn = {
    calls,
    state,
    async beginTransaction() {
      calls.push(['begin']);
      snapshot = JSON.parse(JSON.stringify(state));
    },
    async rollback() {
      calls.push(['rollback']);
      if (snapshot) {
        state.users = snapshot.users;
        state.drivers = snapshot.drivers;
        state.vehicles = snapshot.vehicles;
      }
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
      if (/FROM users u/.test(sql)) {
        const user = state.users.find((row) => row.email === params[0] && row.deleted_at == null);
        return [[user ? {
          id: user.id,
          email: user.email,
          role: user.role,
          is_active: user.is_active ?? 1,
          deleted_at: user.deleted_at ?? null,
          display_name: user.display_name,
        } : undefined].filter(Boolean)];
      }
      if (/FROM drivers\s+WHERE user_id/.test(sql)) {
        const driver = state.drivers.find((row) => Number(row.user_id) === Number(params[0]) && row.deleted_at == null);
        return [[driver ? { id: driver.id, name: driver.name, is_archived: driver.is_archived ?? 0 } : undefined].filter(Boolean)];
      }
      if (/FROM driver_vehicles dv/.test(sql)) {
        const vehicle = state.vehicles.find((row) => row.plate_number === params[0] && row.deleted_at == null);
        if (!vehicle) return [[]];
        const driver = state.drivers.find((row) => Number(row.id) === Number(vehicle.driver_id));
        const user = state.users.find((row) => Number(row.id) === Number(driver?.user_id));
        return [[{
          id: vehicle.id,
          driver_id: vehicle.driver_id,
          driver_name: driver?.name,
          user_email: user?.email,
          user_role: user?.role,
          display_name: user?.display_name,
        }]];
      }
      if (/SELECT id, driver_id\s+FROM driver_vehicles/.test(sql)) {
        const vehicle = state.vehicles.find((row) => row.plate_number === params[0] && row.deleted_at == null);
        return [[vehicle ? { id: vehicle.id, driver_id: vehicle.driver_id } : undefined].filter(Boolean)];
      }
      if (/SELECT id\s+FROM user_profiles/.test(sql)) {
        const user = state.users.find((row) => Number(row.id) === Number(params[0]));
        return [[user ? { id: user.profile_id ?? user.id + 1000 } : undefined].filter(Boolean)];
      }
      if (/UPDATE users\s+SET email =/.test(sql)) {
        if (options.failOnEmailMigration) throw new Error('forced migration failure');
        const user = state.users.find((row) => Number(row.id) === Number(params[1]));
        if (user) user.email = params[0];
        return [{ affectedRows: user ? 1 : 0 }];
      }
      if (/UPDATE users\s+SET/.test(sql)) {
        const userId = params[params.length - 1];
        const user = state.users.find((row) => Number(row.id) === Number(userId));
        if (user) {
          user.role = params.includes(ROLES.DRIVER) ? ROLES.DRIVER : user.role;
          user.is_active = 1;
        }
        return [{ affectedRows: user ? 1 : 0 }];
      }
      if (/UPDATE user_profiles/.test(sql)) {
        const profileId = params[1];
        const user = state.users.find((row) => Number(row.profile_id ?? row.id + 1000) === Number(profileId));
        if (user) user.display_name = params[0];
        return [{ affectedRows: user ? 1 : 0 }];
      }
      if (/UPDATE drivers\s+SET/.test(sql)) {
        const driver = state.drivers.find((row) => Number(row.id) === Number(params[3]));
        if (driver) {
          driver.name = params[0];
          driver.phone = params[1];
          driver.primary_vehicle_type_id = params[2];
          driver.is_active = 1;
          driver.is_archived = 0;
        }
        return [{ affectedRows: driver ? 1 : 0 }];
      }
      if (/UPDATE driver_vehicles\s+SET is_primary = 0/.test(sql)) {
        return [{ affectedRows: state.vehicles.filter((row) => Number(row.driver_id) === Number(params[0])).length }];
      }
      if (/UPDATE driver_vehicles\s+SET vehicle_type_id/.test(sql)) {
        const vehicle = state.vehicles.find((row) => Number(row.id) === Number(params[3]));
        if (vehicle) {
          vehicle.vehicle_type_id = params[0];
          vehicle.model_name = params[1];
          vehicle.color = params[2];
          vehicle.is_primary = 1;
          vehicle.is_active = 1;
        }
        return [{ affectedRows: vehicle ? 1 : 0 }];
      }
      if (/INSERT INTO users/.test(sql) || /INSERT INTO drivers/.test(sql) || /INSERT INTO driver_vehicles/.test(sql)) {
        throw new Error(`Unexpected insert in fake provisioning test: ${sql}`);
      }
      throw new Error(`Unexpected query in fake provisioning test: ${sql}`);
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
    email: 'tride.e2e.admin@example.com',
    display_name: '[E2E] Regression Admin',
  }, 'Admin'));
});

test('provision migrates legacy E2E admin and driver emails without creating new records', async () => {
  const pool = fakeProvisionPool({
    users: [
      {
        id: 11,
        email: 'tride.e2e.admin@invalid.example',
        role: ROLES.ADMIN,
        display_name: '[E2E] Regression Admin',
      },
      {
        id: 22,
        email: 'tride.e2e.driver@invalid.example',
        role: ROLES.DRIVER,
        display_name: '[E2E] Regression Driver',
      },
    ],
    drivers: [
      {
        id: 33,
        user_id: 22,
        name: '[E2E] Regression Driver',
      },
    ],
    vehicles: [
      {
        id: 44,
        driver_id: 33,
        plate_number: 'TEST-E2E-001',
      },
    ],
  });

  const result = await withEnv({
    TRIDE_PROVISION_TEST_ACCOUNTS: '1',
    TRIDE_TEST_ADMIN_PASSWORD: strongPassword('Admin'),
    TRIDE_TEST_DRIVER_PASSWORD: strongPassword('Driver'),
  }, () => provision.provisionAccounts(pool, provision.resolveConfig({ dryRun: false })));

  assert.equal(result.admin.userId, 11);
  assert.equal(result.admin.action, 'migrated');
  assert.equal(result.driver.userId, 22);
  assert.equal(result.driver.driverId, 33);
  assert.equal(result.driver.action, 'updated');
  assert.equal(result.vehicle.vehicleId, 44);
  assert.equal(pool.conn.state.users.find((row) => row.id === 11).email, provision.DEFAULT_ADMIN_EMAIL);
  assert.equal(pool.conn.state.users.find((row) => row.id === 22).email, provision.DEFAULT_DRIVER_EMAIL);
  assert.equal(pool.conn.state.drivers.length, 1);
  assert.equal(pool.conn.state.vehicles.length, 1);
  assert.equal(pool.conn.state.vehicles[0].driver_id, 33);
  assert.equal(pool.conn.calls.some(([kind, sql]) => kind === 'query' && /INSERT INTO/.test(sql)), false);
  assert.equal(pool.conn.calls.some(([kind]) => kind === 'commit'), true);
});

test('provision is idempotent after legacy email migration', async () => {
  const pool = fakeProvisionPool({
    users: [
      {
        id: 11,
        email: provision.DEFAULT_ADMIN_EMAIL,
        role: ROLES.ADMIN,
        display_name: '[E2E] Regression Admin',
      },
      {
        id: 22,
        email: provision.DEFAULT_DRIVER_EMAIL,
        role: ROLES.DRIVER,
        display_name: '[E2E] Regression Driver',
      },
    ],
    drivers: [
      {
        id: 33,
        user_id: 22,
        name: '[E2E] Regression Driver',
      },
    ],
    vehicles: [
      {
        id: 44,
        driver_id: 33,
        plate_number: 'TEST-E2E-001',
      },
    ],
  });

  const result = await withEnv({
    TRIDE_PROVISION_TEST_ACCOUNTS: '1',
    TRIDE_TEST_ADMIN_PASSWORD: strongPassword('Admin'),
    TRIDE_TEST_DRIVER_PASSWORD: strongPassword('Driver'),
  }, () => provision.provisionAccounts(pool, provision.resolveConfig({ dryRun: false })));

  assert.equal(result.admin.userId, 11);
  assert.equal(result.driver.userId, 22);
  assert.equal(result.driver.driverId, 33);
  assert.equal(result.vehicle.vehicleId, 44);
  assert.equal(pool.conn.calls.some(([kind, sql]) => kind === 'query' && /INSERT INTO/.test(sql)), false);
});

test('provision refuses automatic merge when current and legacy emails both exist', async () => {
  const pool = fakeProvisionPool({
    users: [
      {
        id: 11,
        email: provision.DEFAULT_ADMIN_EMAIL,
        role: ROLES.ADMIN,
        display_name: '[E2E] Regression Admin',
      },
      {
        id: 12,
        email: 'tride.e2e.admin@invalid.example',
        role: ROLES.ADMIN,
        display_name: '[E2E] Regression Admin',
      },
    ],
    drivers: [],
    vehicles: [],
  });

  await assert.rejects(
    withEnv({
      TRIDE_PROVISION_TEST_ACCOUNTS: '1',
      TRIDE_TEST_ADMIN_PASSWORD: strongPassword('Admin'),
      TRIDE_TEST_DRIVER_PASSWORD: strongPassword('Driver'),
    }, () => provision.provisionAccounts(pool, provision.resolveConfig({ dryRun: false }))),
    /current and legacy test emails both exist/,
  );
  assert.equal(pool.conn.calls.some(([kind]) => kind === 'rollback'), true);
});

test('provision refuses TEST-E2E-001 when owned by a non-test driver', async () => {
  const pool = fakeProvisionPool({
    users: [
      {
        id: 11,
        email: provision.DEFAULT_ADMIN_EMAIL,
        role: ROLES.ADMIN,
        display_name: '[E2E] Regression Admin',
      },
      {
        id: 22,
        email: 'tride.e2e.driver@invalid.example',
        role: ROLES.DRIVER,
        display_name: '[E2E] Regression Driver',
      },
      {
        id: 55,
        email: 'real.driver@example.com',
        role: ROLES.DRIVER,
        display_name: 'Real Driver',
      },
    ],
    drivers: [
      {
        id: 33,
        user_id: 22,
        name: '[E2E] Regression Driver',
      },
      {
        id: 66,
        user_id: 55,
        name: 'Real Driver',
      },
    ],
    vehicles: [
      {
        id: 44,
        driver_id: 66,
        plate_number: 'TEST-E2E-001',
      },
    ],
  });

  await assert.rejects(
    withEnv({
      TRIDE_PROVISION_TEST_ACCOUNTS: '1',
      TRIDE_TEST_ADMIN_PASSWORD: strongPassword('Admin'),
      TRIDE_TEST_DRIVER_PASSWORD: strongPassword('Driver'),
    }, () => provision.provisionAccounts(pool, provision.resolveConfig({ dryRun: false }))),
    /Test vehicle plate already belongs to another driver/,
  );
});

test('provision rolls back legacy email migration on transaction failure', async () => {
  const pool = fakeProvisionPool({
    users: [
      {
        id: 11,
        email: 'tride.e2e.admin@invalid.example',
        role: ROLES.ADMIN,
        display_name: '[E2E] Regression Admin',
      },
    ],
    drivers: [],
    vehicles: [],
  }, { failOnEmailMigration: true });

  await assert.rejects(
    withEnv({
      TRIDE_PROVISION_TEST_ACCOUNTS: '1',
      TRIDE_TEST_ADMIN_PASSWORD: strongPassword('Admin'),
      TRIDE_TEST_DRIVER_PASSWORD: strongPassword('Driver'),
    }, () => provision.provisionAccounts(pool, provision.resolveConfig({ dryRun: false }))),
    /forced migration failure/,
  );

  assert.equal(pool.conn.state.users[0].email, 'tride.e2e.admin@invalid.example');
  assert.equal(pool.conn.calls.some(([kind]) => kind === 'rollback'), true);
  assert.equal(pool.conn.calls.some(([kind]) => kind === 'commit'), false);
});

test('booking regression runner refuses non-test identities and selects only matching test driver', () => {
  assert.equal(
    runner.isTestIdentity(
      { email: 'tride.e2e.driver@example.com', role: 'DRIVER', name: '[E2E] Regression Driver' },
      'tride.e2e.driver@example.com',
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
    TRIDE_TEST_DRIVER_EMAIL: 'tride.e2e.driver@example.com',
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
    TRIDE_ADMIN_EMAIL: 'tride.e2e.admin@invalid.example',
    TRIDE_ADMIN_PASSWORD: 'secret',
    TRIDE_TEST_DRIVER_EMAIL: 'tride.e2e.driver@example.com',
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
    TRIDE_TEST_ADMIN_EMAIL: 'tride.e2e.admin@example.com',
    TRIDE_ADMIN_EMAIL: 'other.admin@example.com',
    TRIDE_ADMIN_PASSWORD: 'secret',
    TRIDE_TEST_DRIVER_EMAIL: 'tride.e2e.driver@example.com',
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

test('booking regression runner validates customer email with booking schema before live create', () => {
  const valid = runner.bookingPayload({
    customerName: '[E2E] Valid Customer',
    flightNumber: null,
  });
  valid.customer.email = 'regression@example.com';
  assert.doesNotThrow(() => runner.assertValidBookingPayload(valid, 'valid'));

  const dotTest = runner.bookingPayload({
    customerName: '[E2E] Invalid Dot Test',
    flightNumber: null,
  });
  dotTest.customer.email = 'regression@example.test';
  assert.throws(
    () => runner.assertValidBookingPayload(dotTest, 'dot test'),
    /customer.email:string.email:body/,
  );

  const invalidExample = runner.bookingPayload({
    customerName: '[E2E] Invalid Example',
    flightNumber: null,
  });
  invalidExample.customer.email = 'regression@invalid.example';
  assert.throws(
    () => runner.assertValidBookingPayload(invalidExample, 'invalid example'),
    /customer.email:string.email:body/,
  );
});

test('booking regression runner scenarios all use booking-valid customer emails', () => {
  const plan = runner.scenarios();
  assert.equal(plan.length, 5);
  assert.doesNotThrow(() => runner.assertValidScenarioPayloads(plan));
  assert.equal(
    plan.every((item) => item.payload.customer.email === 'regression@example.com'),
    true,
  );
});

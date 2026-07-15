#!/usr/bin/env node
/**
 * Provision isolated staging-only regression accounts.
 *
 * Secrets are read from environment variables only. The script never prints
 * passwords, hashes, tokens, or full request payloads.
 */
const path = require('node:path');

const ROLES = require('../src/constants/roles');
const { loginSchema } = require('../src/validators/auth.validator');
const { hashPassword } = require('../src/utils/passwordHash.util');

const DEFAULT_ADMIN_EMAIL = 'tride.e2e.admin@example.com';
const DEFAULT_DRIVER_EMAIL = 'tride.e2e.driver@example.com';
const DEFAULT_ADMIN_NAME = '[E2E] Regression Admin';
const DEFAULT_DRIVER_NAME = '[E2E] Regression Driver';
const DEFAULT_DRIVER_PHONE = '+66000000999';
const DEFAULT_DRIVER_PLATE = 'TEST-E2E-001';
const DEFAULT_VEHICLE_TYPE_CODE = 'SUV';
const REGRESSION_MARKER = 'AUTOMATED_REGRESSION_TEST';
const TEST_NAME_PREFIX = '[E2E]';
const REQUIRED_LIVE_FLAG = 'TRIDE_PROVISION_TEST_ACCOUNTS';
const RESET_PASSWORD_FLAG = 'TRIDE_RESET_TEST_ACCOUNT_PASSWORDS';
const RESTORE_DRIVER_FLAG = 'TRIDE_RESTORE_ARCHIVED_TEST_DRIVER';

function parseArgs(argv) {
  return {
    dryRun: argv.includes('--dry-run'),
  };
}

function envValue(name, fallback = '') {
  const value = process.env[name];
  return value == null || value === '' ? fallback : String(value);
}

function normalizeEmail(value) {
  return String(value ?? '').trim().toLowerCase();
}

function isValidEmail(email) {
  const { error } = loginSchema.validate({ email: normalizeEmail(email), password: 'validation-only' });
  return !error;
}

function assertPasswordPolicy(name, password) {
  if (password.length < 20) {
    throw new Error(`${name} must be at least 20 characters`);
  }
  if (!/[a-z]/.test(password) || !/[A-Z]/.test(password)) {
    throw new Error(`${name} must include upper and lower case letters`);
  }
  if (!/[0-9]/.test(password)) {
    throw new Error(`${name} must include a number`);
  }
  if (!/[^A-Za-z0-9]/.test(password)) {
    throw new Error(`${name} must include a special character`);
  }
}

function assertTestDisplayName(name, label) {
  if (!String(name ?? '').trim().startsWith(TEST_NAME_PREFIX)) {
    throw new Error(`${label} display name must start with ${TEST_NAME_PREFIX}`);
  }
}

function resolveConfig({ dryRun = false } = {}) {
  const adminEmail = normalizeEmail(envValue('TRIDE_TEST_ADMIN_EMAIL', DEFAULT_ADMIN_EMAIL));
  const driverEmail = normalizeEmail(envValue('TRIDE_TEST_DRIVER_EMAIL', DEFAULT_DRIVER_EMAIL));
  const adminPassword = envValue('TRIDE_TEST_ADMIN_PASSWORD');
  const driverPassword = envValue('TRIDE_TEST_DRIVER_PASSWORD');
  const adminName = envValue('TRIDE_TEST_ADMIN_NAME', DEFAULT_ADMIN_NAME).trim();
  const driverName = envValue('TRIDE_TEST_DRIVER_NAME', DEFAULT_DRIVER_NAME).trim();
  const driverPhone = envValue('TRIDE_TEST_DRIVER_PHONE', DEFAULT_DRIVER_PHONE).trim();
  const driverPlate = envValue('TRIDE_TEST_DRIVER_PLATE', DEFAULT_DRIVER_PLATE).trim().toUpperCase();
  const vehicleTypeCode = envValue('TRIDE_TEST_DRIVER_VEHICLE_TYPE', DEFAULT_VEHICLE_TYPE_CODE)
    .trim()
    .toUpperCase();
  const adminRole = envValue('TRIDE_TEST_ADMIN_ROLE', ROLES.ADMIN).trim().toUpperCase();

  if (!dryRun && process.env[REQUIRED_LIVE_FLAG] !== '1') {
    throw new Error(`Set ${REQUIRED_LIVE_FLAG}=1 to provision staging test accounts`);
  }
  if (!isValidEmail(adminEmail)) throw new Error('TRIDE_TEST_ADMIN_EMAIL must be a valid email');
  if (!isValidEmail(driverEmail)) throw new Error('TRIDE_TEST_DRIVER_EMAIL must be a valid email');
  if (adminEmail === driverEmail) throw new Error('Admin and driver test emails must differ');
  assertTestDisplayName(adminName, 'Admin');
  assertTestDisplayName(driverName, 'Driver');
  if (![ROLES.ADMIN, ROLES.SUPER_ADMIN].includes(adminRole)) {
    throw new Error('TRIDE_TEST_ADMIN_ROLE must be ADMIN or SUPER_ADMIN');
  }
  if (!driverPhone) throw new Error('TRIDE_TEST_DRIVER_PHONE is required');
  if (!driverPlate) throw new Error('TRIDE_TEST_DRIVER_PLATE is required');
  if (!vehicleTypeCode) throw new Error('TRIDE_TEST_DRIVER_VEHICLE_TYPE is required');

  if (!dryRun) {
    if (!adminPassword) throw new Error('TRIDE_TEST_ADMIN_PASSWORD is required');
    if (!driverPassword) throw new Error('TRIDE_TEST_DRIVER_PASSWORD is required');
    assertPasswordPolicy('TRIDE_TEST_ADMIN_PASSWORD', adminPassword);
    assertPasswordPolicy('TRIDE_TEST_DRIVER_PASSWORD', driverPassword);
    if (adminPassword === driverPassword) {
      throw new Error('Admin and driver test passwords must differ');
    }
  }

  return {
    dryRun,
    admin: {
      email: adminEmail,
      password: adminPassword,
      name: adminName,
      role: adminRole,
    },
    driver: {
      email: driverEmail,
      password: driverPassword,
      name: driverName,
      phone: driverPhone,
      plate: driverPlate,
      vehicleTypeCode,
    },
    resetPasswords: process.env[RESET_PASSWORD_FLAG] === '1',
    restoreArchivedDriver: process.env[RESTORE_DRIVER_FLAG] === '1',
  };
}

async function getCurrentDatabase(conn) {
  const [rows] = await conn.query('SELECT DATABASE() AS name');
  return rows[0]?.name ?? null;
}

async function assertTriageDatabase(conn) {
  const databaseName = await getCurrentDatabase(conn);
  if (!databaseName || /ktaxi/i.test(databaseName)) {
    throw new Error('Refusing to provision against a legacy or unknown database');
  }

  const [tables] = await conn.query(
    `
      SELECT TABLE_NAME
      FROM information_schema.TABLES
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME IN ('users', 'user_profiles', 'drivers', 'driver_vehicles', 'vehicle_types')
    `,
  );
  const found = new Set(tables.map((row) => row.TABLE_NAME));
  for (const required of ['users', 'user_profiles', 'drivers', 'driver_vehicles', 'vehicle_types']) {
    if (!found.has(required)) {
      throw new Error(`Required T-Ride table missing: ${required}`);
    }
  }
  return databaseName;
}

async function findUserWithProfile(conn, email) {
  const [rows] = await conn.query(
    `
      SELECT
        u.id,
        u.email,
        u.role,
        u.is_active,
        u.deleted_at,
        up.display_name
      FROM users u
      LEFT JOIN user_profiles up
        ON up.user_id = u.id AND up.deleted_at IS NULL
      WHERE u.email = ?
        AND u.deleted_at IS NULL
      LIMIT 1
    `,
    [email],
  );
  return rows[0] ?? null;
}

function assertExistingUserIsTestAccount(user, label) {
  if (!user) return;
  if (!String(user.display_name ?? '').startsWith(TEST_NAME_PREFIX)) {
    throw new Error(`${label} email already belongs to a non-test account`);
  }
}

async function ensureUserProfile(conn, userId, displayName) {
  const [profiles] = await conn.query(
    `
      SELECT id
      FROM user_profiles
      WHERE user_id = ?
        AND deleted_at IS NULL
      LIMIT 1
    `,
    [userId],
  );
  if (profiles.length) {
    await conn.query(
      `
        UPDATE user_profiles
        SET display_name = ?,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
      `,
      [displayName, profiles[0].id],
    );
    return;
  }
  await conn.query(
    'INSERT INTO user_profiles (user_id, display_name) VALUES (?, ?)',
    [userId, displayName],
  );
}

async function upsertUser(conn, account, role, { resetPassword }) {
  const existing = await findUserWithProfile(conn, account.email);
  assertExistingUserIsTestAccount(existing, role);

  let userId = existing?.id ?? null;
  let action = 'unchanged';

  if (existing) {
    const assignments = [
      'role = ?',
      'is_active = 1',
      'locale = COALESCE(locale, ?)',
      'updated_at = CURRENT_TIMESTAMP',
    ];
    const values = [role, 'en'];
    if (account.phone !== undefined) {
      assignments.unshift('phone = ?');
      values.unshift(account.phone);
    }
    if (resetPassword) {
      assignments.unshift('password_hash = ?');
      values.unshift(await hashPassword(account.password));
    }
    values.push(userId);
    await conn.query(
      `
        UPDATE users
        SET ${assignments.join(', ')}
        WHERE id = ?
      `,
      values,
    );
    action = resetPassword ? 'updated' : 'verified';
  } else {
    const [result] = await conn.query(
      `
        INSERT INTO users (
          email, password_hash, role, phone, locale, is_active
        ) VALUES (?, ?, ?, ?, 'en', 1)
      `,
      [
        account.email,
        await hashPassword(account.password),
        role,
        account.phone ?? null,
      ],
    );
    userId = result.insertId;
    action = 'created';
  }

  await ensureUserProfile(conn, userId, account.name);
  return { userId, action };
}

async function getVehicleType(conn, vehicleTypeCode) {
  const [rows] = await conn.query(
    `
      SELECT id, code
      FROM vehicle_types
      WHERE code = ?
        AND is_active = 1
        AND deleted_at IS NULL
      LIMIT 1
    `,
    [vehicleTypeCode],
  );
  if (!rows[0]) throw new Error(`Vehicle type not found or inactive: ${vehicleTypeCode}`);
  return rows[0];
}

async function ensureDriver(conn, userId, driverConfig, vehicleTypeId, options) {
  const [rows] = await conn.query(
    `
      SELECT id, is_archived, archive_reason
      FROM drivers
      WHERE user_id = ?
        AND deleted_at IS NULL
      LIMIT 1
      FOR UPDATE
    `,
    [userId],
  );

  let driverId = rows[0]?.id ?? null;
  let action = 'verified';
  if (rows[0]?.is_archived === 1 && !options.restoreArchivedDriver) {
    throw new Error('Test driver is archived. Set TRIDE_RESTORE_ARCHIVED_TEST_DRIVER=1 to restore it.');
  }

  if (driverId) {
    await conn.query(
      `
        UPDATE drivers
        SET name = ?,
            phone = ?,
            status = 'OFFLINE',
            is_online = 0,
            is_active = 1,
            is_archived = 0,
            archived_at = NULL,
            archived_by = NULL,
            archive_reason = NULL,
            primary_vehicle_type_id = ?,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
      `,
      [driverConfig.name, driverConfig.phone, vehicleTypeId, driverId],
    );
    action = rows[0].is_archived === 1 ? 'restored' : 'updated';
  } else {
    const [result] = await conn.query(
      `
        INSERT INTO drivers (
          user_id, name, phone, license_number, status, primary_vehicle_type_id,
          is_online, is_active
        ) VALUES (?, ?, ?, ?, 'OFFLINE', ?, 0, 1)
      `,
      [
        userId,
        driverConfig.name,
        driverConfig.phone,
        'E2E-REGRESSION',
        vehicleTypeId,
      ],
    );
    driverId = result.insertId;
    action = 'created';
  }

  return { driverId, action };
}

async function ensureDriverVehicle(conn, driverId, driverConfig, vehicleTypeId) {
  const [plateRows] = await conn.query(
    `
      SELECT id, driver_id
      FROM driver_vehicles
      WHERE plate_number = ?
        AND deleted_at IS NULL
      LIMIT 1
      FOR UPDATE
    `,
    [driverConfig.plate],
  );
  if (plateRows[0] && Number(plateRows[0].driver_id) !== Number(driverId)) {
    throw new Error('Test vehicle plate already belongs to another driver');
  }

  await conn.query(
    `
      UPDATE driver_vehicles
      SET is_primary = 0,
          updated_at = CURRENT_TIMESTAMP
      WHERE driver_id = ?
        AND deleted_at IS NULL
    `,
    [driverId],
  );

  if (plateRows[0]) {
    await conn.query(
      `
        UPDATE driver_vehicles
        SET vehicle_type_id = ?,
            model_name = ?,
            color = ?,
            is_primary = 1,
            is_active = 1,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
      `,
      [vehicleTypeId, 'E2E TEST REGRESSION', 'TEST', plateRows[0].id],
    );
    return { vehicleId: plateRows[0].id, action: 'updated' };
  }

  const [result] = await conn.query(
    `
      INSERT INTO driver_vehicles (
        driver_id, vehicle_type_id, plate_number, model_name, color, is_primary, is_active
      ) VALUES (?, ?, ?, ?, ?, 1, 1)
    `,
    [driverId, vehicleTypeId, driverConfig.plate, 'E2E TEST REGRESSION', 'TEST'],
  );
  return { vehicleId: result.insertId, action: 'created' };
}

async function provisionAccounts(pool, config) {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const databaseName = await assertTriageDatabase(conn);
    const vehicleType = await getVehicleType(conn, config.driver.vehicleTypeCode);

    if (config.dryRun) {
      await conn.rollback();
      return {
        dryRun: true,
        databaseName,
        admin: {
          email: config.admin.email,
          role: config.admin.role,
          displayName: config.admin.name,
        },
        driver: {
          email: config.driver.email,
          displayName: config.driver.name,
          phone: config.driver.phone,
          vehicleTypeCode: vehicleType.code,
          plate: config.driver.plate,
        },
      };
    }

    const adminUser = await upsertUser(conn, config.admin, config.admin.role, {
      resetPassword: config.resetPasswords,
    });
    const driverUser = await upsertUser(
      conn,
      {
        ...config.driver,
        phone: config.driver.phone,
      },
      ROLES.DRIVER,
      { resetPassword: config.resetPasswords },
    );
    const driver = await ensureDriver(
      conn,
      driverUser.userId,
      config.driver,
      vehicleType.id,
      config,
    );
    const vehicle = await ensureDriverVehicle(
      conn,
      driver.driverId,
      config.driver,
      vehicleType.id,
    );

    await conn.commit();
    return {
      dryRun: false,
      databaseName,
      marker: REGRESSION_MARKER,
      admin: {
        action: adminUser.action,
        userId: adminUser.userId,
        email: config.admin.email,
        role: config.admin.role,
        displayName: config.admin.name,
      },
      driver: {
        action: driver.action,
        userId: driverUser.userId,
        driverId: driver.driverId,
        email: config.driver.email,
        displayName: config.driver.name,
        phone: config.driver.phone,
        status: 'OFFLINE',
        isOnline: false,
      },
      vehicle: {
        action: vehicle.action,
        vehicleId: vehicle.vehicleId,
        typeCode: vehicleType.code,
        plate: config.driver.plate,
      },
    };
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}

function printResult(result) {
  console.log(`Dry run: ${result.dryRun ? 'yes' : 'no'}`);
  console.log(`Database: ${result.databaseName}`);
  console.log(`Admin: ${result.admin.email} (${result.admin.role})`);
  console.log(`Admin display: ${result.admin.displayName}`);
  if (result.admin.action) console.log(`Admin action: ${result.admin.action}`);
  console.log(`Driver: ${result.driver.email}`);
  console.log(`Driver display: ${result.driver.displayName}`);
  console.log(`Driver phone: ${result.driver.phone}`);
  if (result.driver.action) console.log(`Driver action: ${result.driver.action}`);
  console.log(`Vehicle: ${result.vehicle?.typeCode ?? result.driver.vehicleTypeCode} / ${result.vehicle?.plate ?? result.driver.plate}`);
  if (result.vehicle?.action) console.log(`Vehicle action: ${result.vehicle.action}`);
  console.log('Passwords: not printed');
}

async function main() {
  require('dotenv').config({
    path: path.join(__dirname, '../.env'),
    override: true,
  });
  const database = require('../src/config/database');
  const args = parseArgs(process.argv.slice(2));
  try {
    const config = resolveConfig(args);
    const result = await provisionAccounts(database.pool, config);
    printResult(result);
  } finally {
    await database.pool.end();
  }
}

if (require.main === module) {
  main().catch((err) => {
    console.error(`Failed: ${err.message}`);
    process.exit(1);
  });
}

module.exports = {
  DEFAULT_ADMIN_EMAIL,
  DEFAULT_DRIVER_EMAIL,
  DEFAULT_ADMIN_NAME,
  DEFAULT_DRIVER_NAME,
  DEFAULT_DRIVER_PHONE,
  DEFAULT_DRIVER_PLATE,
  DEFAULT_VEHICLE_TYPE_CODE,
  REGRESSION_MARKER,
  TEST_NAME_PREFIX,
  assertExistingUserIsTestAccount,
  assertPasswordPolicy,
  parseArgs,
  provisionAccounts,
  resolveConfig,
};

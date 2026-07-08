#!/usr/bin/env node
/**
 * Create or update an ADMIN/SUPER_ADMIN user.
 *
 * Usage:
 *   node scripts/createAdminUser.js --email admin@tride.local --password "$ADMIN_PASSWORD" --name "T-Ride Admin" --role SUPER_ADMIN
 *   node scripts/createAdminUser.js --email admin@tride.local --password "$ADMIN_PASSWORD" --name "T-Ride Admin" --role SUPER_ADMIN --force
 */
const path = require('path');

const ROLES = require('../src/constants/roles');
const { BCRYPT_ROUNDS, hashPassword } = require('../src/utils/passwordHash.util');
const ALLOWED_ROLES = new Set([ROLES.ADMIN, ROLES.SUPER_ADMIN]);

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const item = argv[index];
    if (!item.startsWith('--')) {
      throw new Error(`Unexpected argument: ${item}`);
    }
    const key = item.slice(2);
    if (key === 'force') {
      args.force = true;
      continue;
    }
    const value = argv[index + 1];
    if (!value || value.startsWith('--')) {
      throw new Error(`Missing value for --${key}`);
    }
    args[key] = value;
    index += 1;
  }
  return args;
}

function validateEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

function validatePassword(password) {
  if (password.length < 8) return false;
  if (!/[A-Za-z]/.test(password)) return false;
  if (!/[0-9]/.test(password)) return false;
  return true;
}

function resolveInputs(args) {
  const email = String(args.email ?? '').trim().toLowerCase();
  const password = String(args.password ?? '');
  const name = String(args.name ?? 'T-Ride Admin').trim();
  const role = String(args.role ?? ROLES.ADMIN).trim().toUpperCase();
  const force = args.force === true;

  if (!email || !validateEmail(email)) {
    throw new Error('--email must be a valid email address');
  }
  if (!password || !validatePassword(password)) {
    throw new Error('--password must be at least 8 characters and include letters and numbers');
  }
  if (!name) {
    throw new Error('--name is required');
  }
  if (!ALLOWED_ROLES.has(role)) {
    throw new Error('--role must be ADMIN or SUPER_ADMIN');
  }

  return { email, password, name, role, force };
}

function formatResult(result) {
  return [
    `Email: ${result.email}`,
    `Role: ${result.role}`,
    `Active: ${result.isActive}`,
  ];
}

async function findExistingUser(conn, email) {
  const [rows] = await conn.query(
    `
      SELECT id, email, role
      FROM users
      WHERE email = ? AND deleted_at IS NULL
      LIMIT 1
    `,
    [email],
  );
  return rows[0] || null;
}

async function ensureProfile(conn, userId, displayName) {
  const [profiles] = await conn.query(
    `
      SELECT id
      FROM user_profiles
      WHERE user_id = ? AND deleted_at IS NULL
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
    `
      INSERT INTO user_profiles (user_id, display_name)
      VALUES (?, ?)
    `,
    [userId, displayName],
  );
}

async function createOrUpdateAdminUser(pool, input) {
  const passwordHash = await hashPassword(input.password);
  const conn = await pool.getConnection();

  try {
    await conn.beginTransaction();

    const existing = await findExistingUser(conn, input.email);
    let userId;

    if (existing) {
      if (!input.force) {
        throw new Error('User already exists. Re-run with --force to reset password and update role/profile.');
      }

      userId = existing.id;
      await conn.query(
        `
          UPDATE users
          SET password_hash = ?,
              role = ?,
              locale = COALESCE(locale, 'en'),
              is_active = 1,
              updated_at = CURRENT_TIMESTAMP
          WHERE id = ?
        `,
        [passwordHash, input.role, userId],
      );
    } else {
      const [result] = await conn.query(
        `
          INSERT INTO users (
            email, password_hash, role, locale, is_active
          ) VALUES (?, ?, ?, 'en', 1)
        `,
        [input.email, passwordHash, input.role],
      );
      userId = result.insertId;
    }

    await ensureProfile(conn, userId, input.name);
    await conn.commit();
    return { email: input.email, role: input.role, isActive: true };
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}

async function main() {
  require('dotenv').config({
    path: path.join(__dirname, '../.env'),
    override: true,
  });
  const database = require('../src/config/database');

  try {
    const input = resolveInputs(parseArgs(process.argv.slice(2)));
    const result = await createOrUpdateAdminUser(database.pool, input);
    formatResult(result).forEach((line) => console.log(line));
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
  ALLOWED_ROLES,
  BCRYPT_ROUNDS,
  createOrUpdateAdminUser,
  formatResult,
  parseArgs,
  resolveInputs,
  validatePassword,
};

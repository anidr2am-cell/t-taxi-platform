#!/usr/bin/env node
/**
 * Local development only - create or update a SUPER_ADMIN account.
 *
 * Usage:
 *   ADMIN_EMAIL=admin.local@ttaxi.dev ADMIN_PASSWORD=... npm run create-test-admin
 *
 * Do not store ADMIN_PASSWORD in .env and do not use this as a production migration.
 */
const path = require('path');

const adminEmailFromEnv = process.env.ADMIN_EMAIL;
const adminPasswordFromEnv = process.env.ADMIN_PASSWORD;

require('dotenv').config({
  path: path.join(__dirname, '../.env'),
  override: true,
});

const bcrypt = require('bcryptjs');
const database = require('../src/config/database');
const ROLES = require('../src/constants/roles');

const BCRYPT_ROUNDS = 12;
const DEFAULT_DISPLAY_NAME = 'Local Super Admin';

function resolveInputs() {
  const email = String(adminEmailFromEnv ?? '').trim().toLowerCase();
  const password = String(adminPasswordFromEnv ?? '');

  if (!email) {
    throw new Error('ADMIN_EMAIL is required');
  }

  if (!password) {
    throw new Error('ADMIN_PASSWORD is required');
  }

  return { email, password };
}

async function upsertTestAdmin({ email, password }) {
  const passwordHash = await bcrypt.hash(password, BCRYPT_ROUNDS);
  const conn = await database.pool.getConnection();

  try {
    await conn.beginTransaction();

    const [existingUsers] = await conn.query(
      `
        SELECT id
        FROM users
        WHERE email = ? AND deleted_at IS NULL
        LIMIT 1
      `,
      [email],
    );

    let userId;
    let action;

    if (existingUsers.length) {
      userId = existingUsers[0].id;
      await conn.query(
        `
          UPDATE users
          SET password_hash = ?,
              role = ?,
              is_active = 1,
              updated_at = CURRENT_TIMESTAMP
          WHERE id = ?
        `,
        [passwordHash, ROLES.SUPER_ADMIN, userId],
      );
      action = 'updated';
    } else {
      const [userResult] = await conn.query(
        `
          INSERT INTO users (
            email, password_hash, role, locale, is_active
          ) VALUES (?, ?, ?, 'en', 1)
        `,
        [email, passwordHash, ROLES.SUPER_ADMIN],
      );
      userId = userResult.insertId;
      action = 'created';
    }

    const [profiles] = await conn.query(
      `
        SELECT id, display_name
        FROM user_profiles
        WHERE user_id = ? AND deleted_at IS NULL
        LIMIT 1
      `,
      [userId],
    );

    if (profiles.length) {
      if (!profiles[0].display_name) {
        await conn.query(
          `
            UPDATE user_profiles
            SET display_name = ?, updated_at = CURRENT_TIMESTAMP
            WHERE user_id = ?
          `,
          [DEFAULT_DISPLAY_NAME, userId],
        );
      }
    } else {
      await conn.query(
        `INSERT INTO user_profiles (user_id, display_name) VALUES (?, ?)`,
        [userId, DEFAULT_DISPLAY_NAME],
      );
    }

    await conn.commit();
    return { action, email, role: ROLES.SUPER_ADMIN, userId };
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}

async function main() {
  const inputs = resolveInputs();
  const result = await upsertTestAdmin(inputs);

  console.log(`Result: ${result.action}`);
  console.log(`Email: ${result.email}`);
  console.log(`Role: ${result.role}`);
  console.log(`User ID: ${result.userId}`);
}

main()
  .catch((err) => {
    console.error(`Failed: ${err.message}`);
    process.exit(1);
  })
  .finally(async () => {
    await database.pool.end();
  });

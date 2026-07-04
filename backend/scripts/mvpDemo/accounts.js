const bcrypt = require('bcryptjs');
const ROLES = require('../../src/constants/roles');
const { DEMO_ADMIN, DEMO_DRIVER } = require('./fixtures');
const {
  createOrUpdateAdminUser,
  resolveInputs: resolveAdminInputs,
} = require('../createAdminUser');

const BCRYPT_ROUNDS = 12;

async function upsertDemoAdmin(pool, overrides = {}) {
  const input = resolveAdminInputs({
    email: overrides.email ?? DEMO_ADMIN.email,
    password: overrides.password ?? DEMO_ADMIN.password,
    name: overrides.name ?? DEMO_ADMIN.name,
    role: overrides.role ?? DEMO_ADMIN.role,
    force: true,
  });
  const result = await createOrUpdateAdminUser(pool, input);
  const [rows] = await pool.query(
    `
      SELECT id, email, role
      FROM users
      WHERE email = ? AND deleted_at IS NULL
      LIMIT 1
    `,
    [result.email],
  );
  return rows[0];
}

async function upsertDemoDriver(pool, overrides = {}) {
  const email = String(overrides.email ?? DEMO_DRIVER.email).trim().toLowerCase();
  const name = String(overrides.name ?? DEMO_DRIVER.name).trim();
  const phone = String(overrides.phone ?? DEMO_DRIVER.phone).trim();
  const password = String(overrides.password ?? DEMO_DRIVER.password);
  const passwordHash = await bcrypt.hash(password, BCRYPT_ROUNDS);
  const conn = await pool.getConnection();

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
    if (existingUsers.length) {
      userId = existingUsers[0].id;
      await conn.query(
        `
          UPDATE users
          SET password_hash = ?,
              role = ?,
              phone = ?,
              is_active = 1,
              updated_at = CURRENT_TIMESTAMP
          WHERE id = ?
        `,
        [passwordHash, ROLES.DRIVER, phone, userId],
      );
    } else {
      const [userResult] = await conn.query(
        `
          INSERT INTO users (
            email, password_hash, role, phone, locale, is_active
          ) VALUES (?, ?, ?, ?, 'en', 1)
        `,
        [email, passwordHash, ROLES.DRIVER, phone],
      );
      userId = userResult.insertId;
    }

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
          SET display_name = ?, updated_at = CURRENT_TIMESTAMP
          WHERE user_id = ?
        `,
        [name, userId],
      );
    } else {
      await conn.query(
        `INSERT INTO user_profiles (user_id, display_name) VALUES (?, ?)`,
        [userId, name],
      );
    }

    const [drivers] = await conn.query(
      `
        SELECT id
        FROM drivers
        WHERE user_id = ? AND deleted_at IS NULL
        LIMIT 1
      `,
      [userId],
    );

    let driverId;
    if (drivers.length) {
      driverId = drivers[0].id;
      await conn.query(
        `
          UPDATE drivers
          SET name = ?,
              phone = ?,
              is_active = 1,
              updated_at = CURRENT_TIMESTAMP
          WHERE id = ?
        `,
        [name, phone, driverId],
      );
    } else {
      const [driverResult] = await conn.query(
        `
          INSERT INTO drivers (
            user_id, name, phone, status, is_active, is_online
          ) VALUES (?, ?, ?, 'OFFLINE', 1, 0)
        `,
        [userId, name, phone],
      );
      driverId = driverResult.insertId;
    }

    await conn.commit();
    return { userId, driverId, email, phone, name };
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}

module.exports = {
  upsertDemoAdmin,
  upsertDemoDriver,
};

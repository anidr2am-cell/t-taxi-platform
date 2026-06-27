const database = require('../config/database');

class UserRepository {
  constructor(pool = database.pool) {
    this.pool = pool;
  }

  async findByEmail(email) {
    const [rows] = await this.pool.query(
      `
        SELECT
          u.id,
          u.email,
          u.password_hash,
          u.role,
          u.phone,
          u.phone_country_code,
          u.country_code,
          u.locale,
          u.is_active,
          up.display_name AS name
        FROM users u
        LEFT JOIN user_profiles up
          ON up.user_id = u.id AND up.deleted_at IS NULL
        WHERE u.email = ? AND u.deleted_at IS NULL
      `,
      [email],
    );
    return rows[0] || null;
  }

  async findById(id) {
    const [rows] = await this.pool.query(
      `
        SELECT
          u.id,
          u.email,
          u.password_hash,
          u.role,
          u.phone,
          u.phone_country_code,
          u.country_code,
          u.locale,
          u.is_active,
          up.display_name AS name
        FROM users u
        LEFT JOIN user_profiles up
          ON up.user_id = u.id AND up.deleted_at IS NULL
        WHERE u.id = ? AND u.deleted_at IS NULL
      `,
      [id],
    );
    return rows[0] || null;
  }

  async createCustomerWithProfile({
    email,
    passwordHash,
    phone,
    phoneCountryCode,
    countryCode,
    locale,
    displayName,
  }) {
    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();

      const [userResult] = await conn.query(
        `
          INSERT INTO users (
            email, password_hash, role, phone, phone_country_code, country_code, locale
          ) VALUES (?, ?, 'CUSTOMER', ?, ?, ?, ?)
        `,
        [email, passwordHash, phone, phoneCountryCode, countryCode, locale],
      );

      const userId = userResult.insertId;

      await conn.query(
        `INSERT INTO user_profiles (user_id, display_name) VALUES (?, ?)`,
        [userId, displayName],
      );

      await conn.commit();
      return this.findById(userId);
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }

  async updateLastLoginAt(userId) {
    await this.pool.query(
      `UPDATE users SET last_login_at = CURRENT_TIMESTAMP WHERE id = ?`,
      [userId],
    );
  }

  async findActiveByRoles(roles) {
    if (!roles?.length) return [];
    const [rows] = await this.pool.query(
      `
        SELECT id, role
        FROM users
        WHERE role IN (?) AND is_active = 1 AND deleted_at IS NULL
      `,
      [roles],
    );
    return rows;
  }
}

module.exports = UserRepository;

const database = require('../config/database');

class DriverPasswordResetRepository {
  constructor(pool = database.pool) {
    this.pool = pool;
  }

  async createCode({ userId, codeHash, expiresAt }) {
    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      await conn.query(
        `UPDATE driver_password_reset_codes
         SET used_at = CURRENT_TIMESTAMP
         WHERE user_id = ? AND used_at IS NULL`,
        [userId],
      );
      await conn.query(
        `INSERT INTO driver_password_reset_codes (user_id, code_hash, expires_at)
         VALUES (?, ?, ?)`,
        [userId, codeHash, expiresAt],
      );
      await conn.commit();
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }

  async consumeCodeAndUpdatePassword({ userId, codeHash, passwordHash, maxAttempts }) {
    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      const [rows] = await conn.query(
        `SELECT id, code_hash, expires_at, failed_attempts
         FROM driver_password_reset_codes
         WHERE user_id = ? AND used_at IS NULL
         ORDER BY id DESC LIMIT 1 FOR UPDATE`,
        [userId],
      );
      const reset = rows[0];
      const invalid = !reset
        || reset.failed_attempts >= maxAttempts
        || new Date(reset.expires_at).getTime() <= Date.now()
        || reset.code_hash !== codeHash;

      if (invalid) {
        if (reset && reset.failed_attempts < maxAttempts) {
          await conn.query(
            `UPDATE driver_password_reset_codes
             SET failed_attempts = failed_attempts + 1
             WHERE id = ?`,
            [reset.id],
          );
        }
        await conn.commit();
        return false;
      }

      await conn.query(
        `UPDATE users
         SET password_hash = ?, auth_token_version = auth_token_version + 1,
             updated_at = CURRENT_TIMESTAMP
         WHERE id = ? AND role = 'DRIVER' AND is_active = 1 AND deleted_at IS NULL`,
        [passwordHash, userId],
      );
      await conn.query(
        `UPDATE driver_password_reset_codes SET used_at = CURRENT_TIMESTAMP WHERE id = ?`,
        [reset.id],
      );
      await conn.commit();
      return true;
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }
}

module.exports = DriverPasswordResetRepository;

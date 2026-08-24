const database = require('../config/database');

class SocialAccountRepository {
  constructor(pool = database.pool) {
    this.pool = pool;
  }

  async findByProviderUserId(provider, providerUserId) {
    const [rows] = await this.pool.query(
      `
        SELECT
          sa.id,
          sa.user_id,
          sa.provider,
          sa.provider_user_id,
          sa.provider_email,
          sa.created_at,
          sa.updated_at
        FROM social_accounts sa
        INNER JOIN users u ON u.id = sa.user_id AND u.deleted_at IS NULL
        WHERE sa.provider = ? AND sa.provider_user_id = ?
        LIMIT 1
      `,
      [provider, providerUserId],
    );
    return rows[0] || null;
  }

  async create({ userId, provider, providerUserId, providerEmail }, conn = this.pool) {
    const [result] = await conn.query(
      `
        INSERT INTO social_accounts (
          user_id, provider, provider_user_id, provider_email
        ) VALUES (?, ?, ?, ?)
      `,
      [userId, provider, providerUserId, providerEmail],
    );
    return result.insertId;
  }
}

module.exports = SocialAccountRepository;

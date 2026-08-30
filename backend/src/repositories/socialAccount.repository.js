const database = require('../config/database');
const tokenEncryption = require('../utils/tokenEncryption.util');

function encryptToken(value) {
  return value == null ? null : tokenEncryption.encrypt(value);
}

function decryptToken(value) {
  return value == null ? null : tokenEncryption.decrypt(value);
}

function decryptSocialAccountRow(row) {
  if (!row) {
    return null;
  }

  return {
    ...row,
    access_token: decryptToken(row.access_token),
    refresh_token: decryptToken(row.refresh_token),
  };
}

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
          sa.access_token,
          sa.refresh_token,
          sa.token_expires_at,
          sa.created_at,
          sa.updated_at
        FROM social_accounts sa
        INNER JOIN users u ON u.id = sa.user_id AND u.deleted_at IS NULL
        WHERE sa.provider = ? AND sa.provider_user_id = ?
        LIMIT 1
      `,
      [provider, providerUserId],
    );
    return decryptSocialAccountRow(rows[0] || null);
  }

  async findProvidersByUserId(userId) {
    const [rows] = await this.pool.query(
      `
        SELECT provider
        FROM social_accounts
        WHERE user_id = ?
        ORDER BY created_at ASC, id ASC
      `,
      [userId],
    );
    return rows.map((row) => row.provider);
  }

  async create({
    userId,
    provider,
    providerUserId,
    providerEmail,
    accessToken = null,
    refreshToken = null,
    tokenExpiresAt = null,
  }, conn = this.pool) {
    const [result] = await conn.query(
      `
        INSERT INTO social_accounts (
          user_id,
          provider,
          provider_user_id,
          provider_email,
          access_token,
          refresh_token,
          token_expires_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
      `,
      [
        userId,
        provider,
        providerUserId,
        providerEmail,
        encryptToken(accessToken),
        encryptToken(refreshToken),
        tokenExpiresAt,
      ],
    );
    return result.insertId;
  }

  async updateProviderTokens({
    provider,
    providerUserId,
    accessToken,
    refreshToken,
    tokenExpiresAt,
  }) {
    await this.pool.query(
      `
        UPDATE social_accounts
        SET
          access_token = ?,
          refresh_token = ?,
          token_expires_at = ?,
          updated_at = CURRENT_TIMESTAMP
        WHERE provider = ? AND provider_user_id = ?
      `,
      [
        encryptToken(accessToken),
        encryptToken(refreshToken),
        tokenExpiresAt,
        provider,
        providerUserId,
      ],
    );
  }
}

module.exports = SocialAccountRepository;

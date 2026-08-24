process.env.NODE_ENV = 'test';
process.env.DB_USER = 'test';
process.env.DB_NAME = 'tride_test';
process.env.JWT_ACCESS_SECRET = 'test-access-secret';
process.env.JWT_REFRESH_SECRET = 'test-refresh-secret-value';
process.env.SOCIAL_TOKEN_ENCRYPTION_KEY = Buffer.alloc(32, 9).toString('base64');

const test = require('node:test');
const assert = require('node:assert/strict');

const SOCIAL_PROVIDERS = require('../src/constants/socialProviders');
const SocialAccountRepository = require('../src/repositories/socialAccount.repository');
const { TokenEncryptionError } = require('../src/utils/tokenEncryption.util');

function createMemoryPool() {
  let nextId = 1;
  const rows = [];

  return {
    rows,
    async query(sql, params) {
      if (sql.includes('INSERT INTO social_accounts')) {
        const row = {
          id: nextId,
          user_id: params[0],
          provider: params[1],
          provider_user_id: params[2],
          provider_email: params[3],
          access_token: params[4],
          refresh_token: params[5],
          token_expires_at: params[6],
          created_at: new Date(),
          updated_at: new Date(),
        };
        nextId += 1;
        rows.push(row);
        return [{ insertId: row.id }];
      }

      if (sql.includes('UPDATE social_accounts')) {
        const row = rows.find((item) => (
          item.provider === params[3] && item.provider_user_id === params[4]
        ));
        if (row) {
          row.access_token = params[0];
          row.refresh_token = params[1];
          row.token_expires_at = params[2];
          row.updated_at = new Date();
        }
        return [{ affectedRows: row ? 1 : 0 }];
      }

      if (sql.includes('FROM social_accounts')) {
        const row = rows.find((item) => (
          item.provider === params[0] && item.provider_user_id === params[1]
        ));
        return [[row ? { ...row } : undefined].filter(Boolean)];
      }

      throw new Error(`Unexpected SQL in test pool: ${sql}`);
    },
  };
}

test('create stores encrypted tokens at rest and findByProviderUserId returns plaintext', async () => {
  const pool = createMemoryPool();
  const repository = new SocialAccountRepository(pool);
  const plainAccessToken = 'kakao-access-token-plain';
  const plainRefreshToken = 'kakao-refresh-token-plain';

  await repository.create({
    userId: 42,
    provider: SOCIAL_PROVIDERS.KAKAO,
    providerUserId: 'kakao-user-42',
    providerEmail: 'kakao@example.com',
    accessToken: plainAccessToken,
    refreshToken: plainRefreshToken,
    tokenExpiresAt: new Date('2026-12-31T00:00:00.000Z'),
  });

  assert.equal(pool.rows.length, 1);
  assert.notEqual(pool.rows[0].access_token, plainAccessToken);
  assert.notEqual(pool.rows[0].refresh_token, plainRefreshToken);

  const found = await repository.findByProviderUserId(
    SOCIAL_PROVIDERS.KAKAO,
    'kakao-user-42',
  );

  assert.equal(found.access_token, plainAccessToken);
  assert.equal(found.refresh_token, plainRefreshToken);
});

test('updateProviderTokens encrypts new values and find returns updated plaintext', async () => {
  const pool = createMemoryPool();
  const repository = new SocialAccountRepository(pool);

  await repository.create({
    userId: 99,
    provider: SOCIAL_PROVIDERS.KAKAO,
    providerUserId: 'kakao-user-99',
    providerEmail: null,
    accessToken: 'old-access-token',
    refreshToken: 'old-refresh-token',
    tokenExpiresAt: new Date('2026-01-01T00:00:00.000Z'),
  });

  await repository.updateProviderTokens({
    provider: SOCIAL_PROVIDERS.KAKAO,
    providerUserId: 'kakao-user-99',
    accessToken: 'new-access-token',
    refreshToken: 'new-refresh-token',
    tokenExpiresAt: new Date('2026-06-01T00:00:00.000Z'),
  });

  assert.notEqual(pool.rows[0].access_token, 'new-access-token');
  assert.notEqual(pool.rows[0].refresh_token, 'new-refresh-token');

  const found = await repository.findByProviderUserId(
    SOCIAL_PROVIDERS.KAKAO,
    'kakao-user-99',
  );

  assert.equal(found.access_token, 'new-access-token');
  assert.equal(found.refresh_token, 'new-refresh-token');
});

test('findByProviderUserId throws when stored token cannot be decrypted', async () => {
  const pool = createMemoryPool();
  const repository = new SocialAccountRepository(pool);

  pool.rows.push({
    id: 1,
    user_id: 7,
    provider: SOCIAL_PROVIDERS.KAKAO,
    provider_user_id: 'broken-user',
    provider_email: null,
    access_token: 'corrupted-ciphertext',
    refresh_token: null,
    token_expires_at: null,
    created_at: new Date(),
    updated_at: new Date(),
  });

  await assert.rejects(
    () => repository.findByProviderUserId(SOCIAL_PROVIDERS.KAKAO, 'broken-user'),
    (err) => err instanceof TokenEncryptionError,
  );
});

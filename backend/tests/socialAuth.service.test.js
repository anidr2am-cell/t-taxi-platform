const test = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = 'test';
process.env.DB_USER = 'test';
process.env.DB_NAME = 'tride_test';
process.env.JWT_ACCESS_SECRET = 'test-access-secret';
process.env.JWT_REFRESH_SECRET = 'test-refresh-secret';

const jwt = require('jsonwebtoken');
const SOCIAL_PROVIDERS = require('../src/constants/socialProviders');
const ERROR_CODES = require('../src/constants/errorCodes');
const HTTP_STATUS = require('../src/constants/httpStatus');
const TokenService = require('../src/services/token.service');
const AuthService = require('../src/services/auth.service');
const SocialAuthService = require('../src/services/socialAuth.service');
const { normalizeGoogleIdTokenPayload } = require('../src/services/socialAuth.service');
const RevokedRefreshTokenStore = require('../src/services/revokedRefreshToken.store');

const GOOGLE_SUB = 'google-sub-123';
const GOOGLE_EMAIL = 'social.test@example.com';
const GOOGLE_NAME = 'Social Test User';

function createHarness() {
  let nextUserId = 1000;
  let nextSocialId = 1;
  const users = new Map();
  const profiles = new Map();
  const socialAccounts = [];

  const userRepository = {
    async findByEmail(email) {
      for (const user of users.values()) {
        if (user.email === email) return { ...user };
      }
      return null;
    },
    async findById(id) {
      const user = users.get(id);
      if (!user) return null;
      const profile = profiles.get(id);
      return {
        ...user,
        name: profile?.display_name ?? null,
      };
    },
    async createSocialCustomerWithProfile({ email, displayName, locale = 'ko' }) {
      const id = nextUserId;
      nextUserId += 1;
      users.set(id, {
        id,
        email,
        password_hash: null,
        role: 'CUSTOMER',
        phone: null,
        phone_country_code: null,
        country_code: null,
        locale,
        is_active: 1,
      });
      profiles.set(id, { display_name: displayName });
      return userRepository.findById(id);
    },
    async updateLastLoginAt(userId) {
      const user = users.get(userId);
      if (user) user.last_login_at = new Date();
    },
  };

  const socialAccountRepository = {
    async findByProviderUserId(provider, providerUserId) {
      return socialAccounts.find((row) => (
        row.provider === provider && row.provider_user_id === providerUserId
      )) || null;
    },
    async create({ userId, provider, providerUserId, providerEmail }) {
      const row = {
        id: nextSocialId,
        user_id: userId,
        provider,
        provider_user_id: providerUserId,
        provider_email: providerEmail,
      };
      nextSocialId += 1;
      socialAccounts.push(row);
      return row.id;
    },
  };

  const tokenService = new TokenService(new RevokedRefreshTokenStore());
  const authService = new AuthService(userRepository, tokenService);
  const socialAuthService = new SocialAuthService(
    userRepository,
    socialAccountRepository,
    authService,
    {
      googleClientId: 'test-google-client-id',
      verifyGoogleIdTokenImpl: async (idToken) => {
        if (idToken === 'valid-google-token') {
          return {
            sub: GOOGLE_SUB,
            email: GOOGLE_EMAIL,
            email_verified: true,
            name: GOOGLE_NAME,
          };
        }
        if (idToken === 'valid-google-token-no-email') {
          return {
            sub: 'google-sub-no-email',
            email: null,
            email_verified: true,
            name: GOOGLE_NAME,
          };
        }
        if (idToken === 'valid-google-token-unverified-email') {
          return {
            sub: 'google-sub-unverified',
            email: GOOGLE_EMAIL,
            email_verified: false,
            name: 'Unverified User',
          };
        }
        throw new Error('invalid token');
      },
    },
  );

  return {
    userRepository,
    socialAccountRepository,
    socialAuthService,
    users,
    profiles,
    socialAccounts,
    seedExistingEmailUser({ email = GOOGLE_EMAIL, passwordHash = '$2a$10$hash' } = {}) {
      const id = nextUserId;
      nextUserId += 1;
      users.set(id, {
        id,
        email,
        password_hash: passwordHash,
        role: 'CUSTOMER',
        phone: '+821011111111',
        phone_country_code: '+82',
        country_code: 'KR',
        locale: 'ko',
        is_active: 1,
      });
      profiles.set(id, { display_name: 'Existing User' });
      return id;
    },
  };
}

test('loginWithGoogle creates user, profile, and social_accounts row on first login', async () => {
  const harness = createHarness();

  const result = await harness.socialAuthService.loginWithGoogle('valid-google-token');

  assert.equal(result.user.email, GOOGLE_EMAIL);
  assert.equal(result.user.role, 'CUSTOMER');
  assert.equal(result.user.name, GOOGLE_NAME);
  assert.ok(result.accessToken);
  assert.ok(result.refreshToken);
  assert.equal(harness.users.size, 1);
  assert.equal(harness.socialAccounts.length, 1);
  assert.equal(harness.socialAccounts[0].provider, SOCIAL_PROVIDERS.GOOGLE);
  assert.equal(harness.socialAccounts[0].provider_user_id, GOOGLE_SUB);
  assert.equal(harness.socialAccounts[0].provider_email, GOOGLE_EMAIL);

  const user = [...harness.users.values()][0];
  assert.equal(user.password_hash, null);
});

test('loginWithGoogle links existing email/password customer to Google account', async () => {
  const harness = createHarness();
  const existingUserId = harness.seedExistingEmailUser();

  const result = await harness.socialAuthService.loginWithGoogle('valid-google-token');

  assert.equal(result.user.id, existingUserId);
  assert.equal(result.user.email, GOOGLE_EMAIL);
  assert.equal(harness.users.size, 1);
  assert.equal(harness.socialAccounts.length, 1);
  assert.equal(harness.socialAccounts[0].user_id, existingUserId);
});

test('loginWithGoogle reuses the same user_id for an already linked account', async () => {
  const harness = createHarness();

  const first = await harness.socialAuthService.loginWithGoogle('valid-google-token');
  const second = await harness.socialAuthService.loginWithGoogle('valid-google-token');

  assert.equal(first.user.id, second.user.id);
  assert.equal(harness.users.size, 1);
  assert.equal(harness.socialAccounts.length, 1);
});

test('loginWithGoogle rejects invalid or expired id tokens', async () => {
  const harness = createHarness();

  await assert.rejects(
    () => harness.socialAuthService.loginWithGoogle('bad-token'),
    (err) => {
      assert.equal(err.statusCode, HTTP_STATUS.UNAUTHORIZED);
      assert.equal(err.errorCode, ERROR_CODES.AUTH_INVALID);
      return true;
    },
  );
});

test('loginWithGoogle rejects tokens without email for new accounts', async () => {
  const harness = createHarness();

  await assert.rejects(
    () => harness.socialAuthService.loginWithGoogle('valid-google-token-no-email'),
    (err) => {
      assert.equal(err.statusCode, HTTP_STATUS.BAD_REQUEST);
      assert.equal(err.errorCode, ERROR_CODES.VALIDATION_ERROR);
      return true;
    },
  );
});

test('loginWithGoogle returns JWT payload compatible with existing auth flow', async () => {
  const harness = createHarness();
  const result = await harness.socialAuthService.loginWithGoogle('valid-google-token');
  const payload = jwt.decode(result.accessToken);

  assert.equal(String(payload.sub), String(result.user.id));
  assert.equal(payload.email, GOOGLE_EMAIL);
  assert.equal(payload.role, 'CUSTOMER');
  assert.equal(payload.type, 'access');
});

test('normalizeGoogleIdTokenPayload ignores email when email_verified is false', () => {
  const normalized = normalizeGoogleIdTokenPayload({
    sub: 'google-sub-unverified',
    email: GOOGLE_EMAIL,
    email_verified: false,
    name: 'Unverified User',
  });

  assert.equal(normalized.providerUserId, 'google-sub-unverified');
  assert.equal(normalized.email, null);
  assert.equal(normalized.name, 'Unverified User');
});

test('loginWithGoogle does not merge unverified email into an existing account', async () => {
  const harness = createHarness();
  const existingUserId = harness.seedExistingEmailUser();

  await assert.rejects(
    () => harness.socialAuthService.loginWithGoogle('valid-google-token-unverified-email'),
    (err) => {
      assert.equal(err.statusCode, HTTP_STATUS.BAD_REQUEST);
      assert.equal(err.errorCode, ERROR_CODES.VALIDATION_ERROR);
      return true;
    },
  );

  assert.equal(harness.users.size, 1);
  assert.equal(harness.socialAccounts.length, 0);
  assert.equal([...harness.users.keys()][0], existingUserId);
});

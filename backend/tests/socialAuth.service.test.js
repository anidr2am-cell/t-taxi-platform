const test = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = 'test';
process.env.DB_USER = 'test';
process.env.DB_NAME = 'tride_test';
process.env.JWT_ACCESS_SECRET = 'test-access-secret';
process.env.JWT_REFRESH_SECRET = 'test-refresh-secret';
process.env.SOCIAL_TOKEN_ENCRYPTION_KEY = Buffer.alloc(32, 4).toString('base64');

const jwt = require('jsonwebtoken');
const SOCIAL_PROVIDERS = require('../src/constants/socialProviders');
const ERROR_CODES = require('../src/constants/errorCodes');
const HTTP_STATUS = require('../src/constants/httpStatus');
const TokenService = require('../src/services/token.service');
const AuthService = require('../src/services/auth.service');
const SocialAuthService = require('../src/services/socialAuth.service');
const {
  normalizeGoogleIdTokenPayload,
  buildKakaoPlaceholderEmail,
  computeTokenExpiresAt,
  buildKakaoAuthorizationCodePrefix,
  buildKakaoTokenExchangeFailureLogContext,
  buildKakaoUserMeFailureLogContext,
} = require('../src/services/socialAuth.service');
const logger = require('../src/utils/logger');
const RevokedRefreshTokenStore = require('../src/services/revokedRefreshToken.store');

const GOOGLE_SUB = 'google-sub-123';
const GOOGLE_EMAIL = 'social.test@example.com';
const GOOGLE_NAME = 'Social Test User';

const KAKAO_USER_ID = 'kakao-user-123';
const KAKAO_EMAIL = 'kakao.test@example.com';
const KAKAO_NAME = 'Kakao Test User';
const KAKAO_REDIRECT_URI = 'https://trider.taxi/auth/kakao/callback';

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
    async create({
      userId,
      provider,
      providerUserId,
      providerEmail,
      accessToken = null,
      refreshToken = null,
      tokenExpiresAt = null,
    }) {
      const row = {
        id: nextSocialId,
        user_id: userId,
        provider,
        provider_user_id: providerUserId,
        provider_email: providerEmail,
        access_token: accessToken,
        refresh_token: refreshToken,
        token_expires_at: tokenExpiresAt,
      };
      nextSocialId += 1;
      socialAccounts.push(row);
      return row.id;
    },
    async updateProviderTokens({
      provider,
      providerUserId,
      accessToken,
      refreshToken,
      tokenExpiresAt,
    }) {
      const row = socialAccounts.find((item) => (
        item.provider === provider && item.provider_user_id === providerUserId
      ));
      if (!row) return;
      row.access_token = accessToken;
      row.refresh_token = refreshToken;
      row.token_expires_at = tokenExpiresAt;
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
      exchangeKakaoCodeImpl: async (code, redirectUri) => {
        if (redirectUri !== KAKAO_REDIRECT_URI) {
          throw new Error('unexpected redirect uri');
        }
        if (code === 'valid-kakao-code') {
          return {
            providerUserId: KAKAO_USER_ID,
            email: KAKAO_EMAIL,
            name: KAKAO_NAME,
            accessToken: 'kakao-access-token-v1',
            refreshToken: 'kakao-refresh-token-v1',
            expiresIn: 3600,
          };
        }
        if (code === 'valid-kakao-code-no-email') {
          return {
            providerUserId: 'kakao-user-no-email',
            email: null,
            name: 'Kakao No Email',
            accessToken: 'kakao-access-token-no-email',
            refreshToken: 'kakao-refresh-token-no-email',
            expiresIn: 7200,
          };
        }
        if (code === 'valid-kakao-code-relogin') {
          return {
            providerUserId: 'kakao-user-relogin',
            email: 'relogin@example.com',
            name: 'Kakao Relogin',
            accessToken: 'kakao-access-token-v2',
            refreshToken: 'kakao-refresh-token-v2',
            expiresIn: 1800,
          };
        }
        throw new Error('invalid kakao code');
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

test('loginWithKakao creates user and stores Kakao OAuth tokens on first login', async () => {
  const harness = createHarness();
  const before = Date.now();

  const result = await harness.socialAuthService.loginWithKakao(
    'valid-kakao-code',
    KAKAO_REDIRECT_URI,
  );

  assert.equal(result.user.email, KAKAO_EMAIL);
  assert.equal(result.user.name, KAKAO_NAME);
  assert.ok(result.accessToken);
  assert.ok(result.refreshToken);
  assert.equal(harness.socialAccounts.length, 1);
  assert.equal(harness.socialAccounts[0].provider, SOCIAL_PROVIDERS.KAKAO);
  assert.equal(harness.socialAccounts[0].provider_user_id, KAKAO_USER_ID);
  assert.equal(harness.socialAccounts[0].provider_email, KAKAO_EMAIL);
  assert.equal(harness.socialAccounts[0].access_token, 'kakao-access-token-v1');
  assert.equal(harness.socialAccounts[0].refresh_token, 'kakao-refresh-token-v1');
  assert.ok(harness.socialAccounts[0].token_expires_at instanceof Date);
  assert.ok(harness.socialAccounts[0].token_expires_at.getTime() >= before + 3600 * 1000 - 1000);
});

test('loginWithKakao allows signup when Kakao account has no email', async () => {
  const harness = createHarness();

  const result = await harness.socialAuthService.loginWithKakao(
    'valid-kakao-code-no-email',
    KAKAO_REDIRECT_URI,
  );

  assert.equal(result.user.email, buildKakaoPlaceholderEmail('kakao-user-no-email'));
  assert.equal(result.user.name, 'Kakao No Email');
  assert.equal(harness.socialAccounts.length, 1);
  assert.equal(harness.socialAccounts[0].provider_email, null);
  assert.equal(harness.socialAccounts[0].access_token, 'kakao-access-token-no-email');
});

test('loginWithKakao updates stored tokens on re-login', async () => {
  const harness = createHarness();

  await harness.socialAuthService.loginWithKakao(
    'valid-kakao-code-relogin',
    KAKAO_REDIRECT_URI,
  );

  const firstRow = harness.socialAccounts[0];
  assert.equal(firstRow.access_token, 'kakao-access-token-v2');
  assert.equal(firstRow.refresh_token, 'kakao-refresh-token-v2');

  harness.socialAuthService.exchangeKakaoCodeImpl = async () => ({
    providerUserId: 'kakao-user-relogin',
    email: 'relogin@example.com',
    name: 'Kakao Relogin',
    accessToken: 'kakao-access-token-v3',
    refreshToken: 'kakao-refresh-token-v3',
    expiresIn: 900,
  });

  const second = await harness.socialAuthService.loginWithKakao(
    'valid-kakao-code-relogin',
    KAKAO_REDIRECT_URI,
  );

  assert.equal(second.user.email, 'relogin@example.com');
  assert.equal(harness.socialAccounts.length, 1);
  assert.equal(harness.socialAccounts[0].access_token, 'kakao-access-token-v3');
  assert.equal(harness.socialAccounts[0].refresh_token, 'kakao-refresh-token-v3');
});

test('loginWithKakao rejects invalid authorization code', async () => {
  const harness = createHarness();

  await assert.rejects(
    () => harness.socialAuthService.loginWithKakao('bad-kakao-code', KAKAO_REDIRECT_URI),
    (err) => {
      assert.equal(err.statusCode, HTTP_STATUS.UNAUTHORIZED);
      assert.equal(err.errorCode, ERROR_CODES.AUTH_INVALID);
      return true;
    },
  );
});

test('computeTokenExpiresAt returns null for invalid expiresIn', () => {
  assert.equal(computeTokenExpiresAt(null), null);
  assert.equal(computeTokenExpiresAt('not-a-number'), null);
  assert.equal(computeTokenExpiresAt(-1), null);
});

test('buildKakaoTokenExchangeFailureLogContext keeps only safe diagnostic fields', () => {
  const context = buildKakaoTokenExchangeFailureLogContext({
    status: 400,
    redirectUri: KAKAO_REDIRECT_URI,
    authorizationCode: 'abcdefghijklmnop',
    tokenJson: {
      error: 'invalid_grant',
      error_description: 'authorization code not found',
      error_code: 'KOE320',
      access_token: 'must-not-leak',
      refresh_token: 'must-not-leak',
    },
  });

  assert.deepEqual(context, {
    status: 400,
    redirectUri: KAKAO_REDIRECT_URI,
    authorizationCodePrefix: 'abcdefgh',
    kakaoError: 'invalid_grant',
    kakaoErrorDescription: 'authorization code not found',
    kakaoErrorCode: 'KOE320',
  });
  assert.equal(JSON.stringify(context).includes('must-not-leak'), false);
  assert.equal(JSON.stringify(context).includes('abcdefghijklmnop'), false);
});

test('buildKakaoUserMeFailureLogContext keeps only safe diagnostic fields', () => {
  const context = buildKakaoUserMeFailureLogContext({
    status: 401,
    userJson: {
      msg: 'invalid token',
      code: -401,
      access_token: 'must-not-leak',
    },
  });

  assert.deepEqual(context, {
    status: 401,
    kakaoMsg: 'invalid token',
    kakaoErrorCode: -401,
  });
  assert.equal(JSON.stringify(context).includes('must-not-leak'), false);
});

test('buildKakaoAuthorizationCodePrefix returns at most 8 characters', () => {
  assert.equal(buildKakaoAuthorizationCodePrefix('abc'), 'abc');
  assert.equal(buildKakaoAuthorizationCodePrefix('1234567890'), '12345678');
  assert.equal(buildKakaoAuthorizationCodePrefix('   '), null);
});

function createDirectKakaoExchangeService({ kakaoClientSecret = null, fetchImpl }) {
  return new SocialAuthService({}, {}, {}, {
    kakaoRestApiKey: 'test-kakao-rest-api-key',
    kakaoClientSecret,
    fetchImpl,
  });
}

test('exchangeKakaoCode logs Kakao error fields without leaking tokens on token failure', async () => {
  const warnCalls = [];
  const originalWarn = logger.warn;
  logger.warn = (...args) => {
    warnCalls.push(args);
  };

  try {
    const service = createDirectKakaoExchangeService({
      fetchImpl: async () => ({
        ok: false,
        status: 400,
        json: async () => ({
          error: 'invalid_grant',
          error_description: 'authorization code not found',
          error_code: 'KOE320',
          access_token: 'must-not-leak',
          refresh_token: 'must-not-leak',
        }),
      }),
    });

    await assert.rejects(
      () => service.exchangeKakaoCode('abcdefghijklmnop', KAKAO_REDIRECT_URI),
      (err) => {
        assert.equal(err.statusCode, HTTP_STATUS.UNAUTHORIZED);
        assert.equal(err.errorCode, ERROR_CODES.AUTH_INVALID);
        return true;
      },
    );

    assert.equal(warnCalls.length, 1);
    assert.equal(warnCalls[0][0], 'Kakao token exchange failed');
    assert.deepEqual(warnCalls[0][1], {
      status: 400,
      redirectUri: KAKAO_REDIRECT_URI,
      authorizationCodePrefix: 'abcdefgh',
      kakaoError: 'invalid_grant',
      kakaoErrorDescription: 'authorization code not found',
      kakaoErrorCode: 'KOE320',
    });
    assert.equal(JSON.stringify(warnCalls).includes('must-not-leak'), false);
    assert.equal(JSON.stringify(warnCalls).includes('abcdefghijklmnop'), false);
  } finally {
    logger.warn = originalWarn;
  }
});

test('exchangeKakaoCode includes client_secret only when configured', async () => {
  let tokenRequestBody = null;

  const successFetchImpl = async (url, options) => {
    if (String(url).includes('/oauth/token')) {
      tokenRequestBody = options.body;
      return {
        ok: true,
        status: 200,
        json: async () => ({
          access_token: 'kakao-access-token',
          refresh_token: 'kakao-refresh-token',
          expires_in: 3600,
        }),
      };
    }

    return {
      ok: true,
      status: 200,
      json: async () => ({
        id: KAKAO_USER_ID,
        kakao_account: { email: KAKAO_EMAIL },
        properties: { nickname: KAKAO_NAME },
      }),
    };
  };

  const withSecret = createDirectKakaoExchangeService({
    kakaoClientSecret: 'configured-client-secret',
    fetchImpl: successFetchImpl,
  });
  await withSecret.exchangeKakaoCode('valid-kakao-code', KAKAO_REDIRECT_URI);
  assert.match(String(tokenRequestBody), /client_secret=configured-client-secret/);

  tokenRequestBody = null;
  const withoutSecret = createDirectKakaoExchangeService({
    kakaoClientSecret: '',
    fetchImpl: successFetchImpl,
  });
  await withoutSecret.exchangeKakaoCode('valid-kakao-code', KAKAO_REDIRECT_URI);
  assert.doesNotMatch(String(tokenRequestBody), /client_secret=/);
});

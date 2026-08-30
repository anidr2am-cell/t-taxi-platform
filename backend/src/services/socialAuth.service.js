const { OAuth2Client } = require('google-auth-library');
const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const ROLES = require('../constants/roles');
const SOCIAL_PROVIDERS = require('../constants/socialProviders');
const logger = require('../utils/logger');

const KAKAO_TOKEN_URL = 'https://kauth.kakao.com/oauth/token';
const KAKAO_USER_ME_URL = 'https://kapi.kakao.com/v2/user/me';
const LINE_TOKEN_URL = 'https://api.line.me/oauth2/v2.1/token';
const LINE_VERIFY_URL = 'https://api.line.me/oauth2/v2.1/verify';

function normalizeGoogleIdTokenPayload(payload) {
  if (!payload?.sub) {
    throw new AppError('Invalid Google ID token', {
      statusCode: HTTP_STATUS.UNAUTHORIZED,
      errorCode: ERROR_CODES.AUTH_INVALID,
    });
  }

  return {
    providerUserId: payload.sub,
    email: payload.email_verified === true
      ? (payload.email ? payload.email.trim().toLowerCase() : null)
      : null,
    name: payload.name || null,
  };
}

function buildKakaoPlaceholderEmail(providerUserId) {
  return `kakao_${providerUserId}@social.trider.local`;
}

function buildLinePlaceholderEmail(providerUserId) {
  return `line_${providerUserId}@social.trider.local`;
}

function buildSocialPlaceholderEmail(provider, providerUserId) {
  if (provider === SOCIAL_PROVIDERS.LINE) {
    return buildLinePlaceholderEmail(providerUserId);
  }
  if (provider === SOCIAL_PROVIDERS.KAKAO) {
    return buildKakaoPlaceholderEmail(providerUserId);
  }
  return `social_${providerUserId}@social.trider.local`;
}

function computeTokenExpiresAt(expiresIn) {
  const seconds = Number(expiresIn);
  if (!Number.isFinite(seconds) || seconds <= 0) {
    return null;
  }
  return new Date(Date.now() + seconds * 1000);
}

function buildAuthorizationCodePrefix(authorizationCode) {
  if (authorizationCode == null) {
    return null;
  }

  const normalized = String(authorizationCode).trim();
  if (!normalized) {
    return null;
  }

  return normalized.slice(0, 8);
}

function buildKakaoAuthorizationCodePrefix(authorizationCode) {
  return buildAuthorizationCodePrefix(authorizationCode);
}

function buildKakaoTokenExchangeFailureLogContext({
  status,
  redirectUri,
  authorizationCode,
  tokenJson,
}) {
  return {
    status,
    redirectUri,
    authorizationCodePrefix: buildKakaoAuthorizationCodePrefix(authorizationCode),
    kakaoError: tokenJson?.error ?? null,
    kakaoErrorDescription: tokenJson?.error_description ?? null,
    kakaoErrorCode: tokenJson?.error_code ?? null,
  };
}

function buildKakaoUserMeFailureLogContext({ status, userJson }) {
  return {
    status,
    kakaoMsg: userJson?.msg ?? null,
    kakaoErrorCode: userJson?.code ?? null,
  };
}

function buildLineTokenExchangeFailureLogContext({
  status,
  redirectUri,
  authorizationCode,
  tokenJson,
}) {
  return {
    status,
    redirectUri,
    authorizationCodePrefix: buildAuthorizationCodePrefix(authorizationCode),
    lineError: tokenJson?.error ?? null,
    lineErrorDescription: tokenJson?.error_description ?? null,
  };
}

function buildLineVerifyFailureLogContext({ status, verifyJson }) {
  return {
    status,
    lineError: verifyJson?.error ?? null,
    lineErrorDescription: verifyJson?.error_description ?? null,
  };
}

function normalizeLineIdTokenPayload(payload) {
  const providerUserId = payload?.sub != null ? String(payload.sub) : null;
  if (!providerUserId) {
    throw new AppError('Invalid LINE authorization code', {
      statusCode: HTTP_STATUS.UNAUTHORIZED,
      errorCode: ERROR_CODES.AUTH_INVALID,
    });
  }

  const email = payload.email
    ? payload.email.trim().toLowerCase()
    : null;

  return {
    providerUserId,
    email,
    name: payload.name || null,
  };
}

function normalizeKakaoUserPayload(payload) {
  const providerUserId = payload?.id != null ? String(payload.id) : null;
  if (!providerUserId) {
    throw new AppError('Invalid Kakao authorization code', {
      statusCode: HTTP_STATUS.UNAUTHORIZED,
      errorCode: ERROR_CODES.AUTH_INVALID,
    });
  }

  const email = payload.kakao_account?.email
    ? payload.kakao_account.email.trim().toLowerCase()
    : null;

  return {
    providerUserId,
    email,
    name: payload.properties?.nickname || null,
  };
}

class SocialAuthService {
  constructor(userRepository, socialAccountRepository, authService, options = {}) {
    this.userRepository = userRepository;
    this.socialAccountRepository = socialAccountRepository;
    this.authService = authService;
    this.googleClientId = options.googleClientId || null;
    this.kakaoRestApiKey = options.kakaoRestApiKey || null;
    this.kakaoClientSecret = options.kakaoClientSecret || null;
    this.lineLoginChannelId = options.lineLoginChannelId || null;
    this.lineLoginChannelSecret = options.lineLoginChannelSecret || null;
    this.verifyGoogleIdTokenImpl = options.verifyGoogleIdTokenImpl || null;
    this.exchangeKakaoCodeImpl = options.exchangeKakaoCodeImpl || null;
    this.exchangeLineCodeImpl = options.exchangeLineCodeImpl || null;
    this.fetchImpl = options.fetchImpl || globalThis.fetch;
  }

  async verifyGoogleIdToken(idToken) {
    let payload;

    if (this.verifyGoogleIdTokenImpl) {
      try {
        payload = await this.verifyGoogleIdTokenImpl(idToken);
      } catch (err) {
        if (err instanceof AppError) {
          throw err;
        }
        throw new AppError('Invalid Google ID token', {
          statusCode: HTTP_STATUS.UNAUTHORIZED,
          errorCode: ERROR_CODES.AUTH_INVALID,
        });
      }
      return normalizeGoogleIdTokenPayload(payload);
    }

    if (!this.googleClientId) {
      throw new AppError('Google sign-in is not configured', {
        statusCode: HTTP_STATUS.SERVICE_UNAVAILABLE,
        errorCode: ERROR_CODES.EXTERNAL_API_ERROR,
      });
    }

    try {
      const client = new OAuth2Client(this.googleClientId);
      const ticket = await client.verifyIdToken({
        idToken,
        audience: this.googleClientId,
      });
      return normalizeGoogleIdTokenPayload(ticket.getPayload());
    } catch (err) {
      if (err instanceof AppError) {
        throw err;
      }
      throw new AppError('Invalid Google ID token', {
        statusCode: HTTP_STATUS.UNAUTHORIZED,
        errorCode: ERROR_CODES.AUTH_INVALID,
      });
    }
  }

  async exchangeKakaoCode(authorizationCode, redirectUri) {
    if (this.exchangeKakaoCodeImpl) {
      try {
        return await this.exchangeKakaoCodeImpl(authorizationCode, redirectUri);
      } catch (err) {
        if (err instanceof AppError) {
          throw err;
        }
        throw new AppError('Invalid Kakao authorization code', {
          statusCode: HTTP_STATUS.UNAUTHORIZED,
          errorCode: ERROR_CODES.AUTH_INVALID,
        });
      }
    }

    if (!this.kakaoRestApiKey) {
      throw new AppError('Kakao sign-in is not configured', {
        statusCode: HTTP_STATUS.SERVICE_UNAVAILABLE,
        errorCode: ERROR_CODES.EXTERNAL_API_ERROR,
      });
    }

    const tokenBody = new URLSearchParams({
      grant_type: 'authorization_code',
      client_id: this.kakaoRestApiKey,
      redirect_uri: redirectUri,
      code: authorizationCode,
    });
    if (this.kakaoClientSecret) {
      tokenBody.set('client_secret', this.kakaoClientSecret);
    }

    let tokenResponse;
    try {
      tokenResponse = await this.fetchImpl(KAKAO_TOKEN_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded;charset=utf-8',
        },
        body: tokenBody.toString(),
      });
    } catch (err) {
      throw new AppError('Kakao sign-in is temporarily unavailable', {
        statusCode: HTTP_STATUS.SERVICE_UNAVAILABLE,
        errorCode: ERROR_CODES.EXTERNAL_API_ERROR,
      });
    }

    const tokenJson = await tokenResponse.json();
    if (!tokenResponse.ok || !tokenJson.access_token) {
      logger.warn(
        'Kakao token exchange failed',
        buildKakaoTokenExchangeFailureLogContext({
          status: tokenResponse.status,
          redirectUri,
          authorizationCode,
          tokenJson,
        }),
      );
      throw new AppError('Invalid Kakao authorization code', {
        statusCode: HTTP_STATUS.UNAUTHORIZED,
        errorCode: ERROR_CODES.AUTH_INVALID,
      });
    }

    let userResponse;
    try {
      userResponse = await this.fetchImpl(KAKAO_USER_ME_URL, {
        method: 'GET',
        headers: {
          Authorization: `Bearer ${tokenJson.access_token}`,
        },
      });
    } catch (err) {
      throw new AppError('Kakao sign-in is temporarily unavailable', {
        statusCode: HTTP_STATUS.SERVICE_UNAVAILABLE,
        errorCode: ERROR_CODES.EXTERNAL_API_ERROR,
      });
    }

    const userJson = await userResponse.json();
    if (!userResponse.ok) {
      logger.warn(
        'Kakao user profile fetch failed',
        buildKakaoUserMeFailureLogContext({
          status: userResponse.status,
          userJson,
        }),
      );
      throw new AppError('Invalid Kakao authorization code', {
        statusCode: HTTP_STATUS.UNAUTHORIZED,
        errorCode: ERROR_CODES.AUTH_INVALID,
      });
    }

    const profile = normalizeKakaoUserPayload(userJson);
    return {
      ...profile,
      accessToken: tokenJson.access_token,
      refreshToken: tokenJson.refresh_token || null,
      expiresIn: tokenJson.expires_in ?? null,
    };
  }

  async exchangeLineCode(authorizationCode, redirectUri) {
    if (this.exchangeLineCodeImpl) {
      try {
        return await this.exchangeLineCodeImpl(authorizationCode, redirectUri);
      } catch (err) {
        if (err instanceof AppError) {
          throw err;
        }
        throw new AppError('Invalid LINE authorization code', {
          statusCode: HTTP_STATUS.UNAUTHORIZED,
          errorCode: ERROR_CODES.AUTH_INVALID,
        });
      }
    }

    if (!this.lineLoginChannelId || !this.lineLoginChannelSecret) {
      throw new AppError('LINE sign-in is not configured', {
        statusCode: HTTP_STATUS.SERVICE_UNAVAILABLE,
        errorCode: ERROR_CODES.EXTERNAL_API_ERROR,
      });
    }

    const tokenBody = new URLSearchParams({
      grant_type: 'authorization_code',
      client_id: this.lineLoginChannelId,
      client_secret: this.lineLoginChannelSecret,
      redirect_uri: redirectUri,
      code: authorizationCode,
    });

    let tokenResponse;
    try {
      tokenResponse = await this.fetchImpl(LINE_TOKEN_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: tokenBody.toString(),
      });
    } catch (err) {
      throw new AppError('LINE sign-in is temporarily unavailable', {
        statusCode: HTTP_STATUS.SERVICE_UNAVAILABLE,
        errorCode: ERROR_CODES.EXTERNAL_API_ERROR,
      });
    }

    const tokenJson = await tokenResponse.json();
    if (!tokenResponse.ok || !tokenJson.id_token) {
      logger.warn(
        'LINE token exchange failed',
        buildLineTokenExchangeFailureLogContext({
          status: tokenResponse.status,
          redirectUri,
          authorizationCode,
          tokenJson,
        }),
      );
      throw new AppError('Invalid LINE authorization code', {
        statusCode: HTTP_STATUS.UNAUTHORIZED,
        errorCode: ERROR_CODES.AUTH_INVALID,
      });
    }

    const verifyBody = new URLSearchParams({
      id_token: tokenJson.id_token,
      client_id: this.lineLoginChannelId,
    });

    let verifyResponse;
    try {
      verifyResponse = await this.fetchImpl(LINE_VERIFY_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: verifyBody.toString(),
      });
    } catch (err) {
      throw new AppError('LINE sign-in is temporarily unavailable', {
        statusCode: HTTP_STATUS.SERVICE_UNAVAILABLE,
        errorCode: ERROR_CODES.EXTERNAL_API_ERROR,
      });
    }

    const verifyJson = await verifyResponse.json();
    if (!verifyResponse.ok) {
      logger.warn(
        'LINE id_token verify failed',
        buildLineVerifyFailureLogContext({
          status: verifyResponse.status,
          verifyJson,
        }),
      );
      throw new AppError('Invalid LINE authorization code', {
        statusCode: HTTP_STATUS.UNAUTHORIZED,
        errorCode: ERROR_CODES.AUTH_INVALID,
      });
    }

    return normalizeLineIdTokenPayload(verifyJson);
  }

  async loginWithGoogle(idToken) {
    const profile = await this.verifyGoogleIdToken(idToken);
    return this.loginOrRegisterWithSocial({
      provider: SOCIAL_PROVIDERS.GOOGLE,
      providerUserId: profile.providerUserId,
      email: profile.email,
      name: profile.name,
    });
  }

  async loginWithKakao(code, redirectUri) {
    const profile = await this.exchangeKakaoCode(code, redirectUri);
    return this.loginOrRegisterWithSocial({
      provider: SOCIAL_PROVIDERS.KAKAO,
      providerUserId: profile.providerUserId,
      email: profile.email,
      name: profile.name,
      providerTokens: {
        accessToken: profile.accessToken,
        refreshToken: profile.refreshToken,
        tokenExpiresAt: computeTokenExpiresAt(profile.expiresIn),
      },
    });
  }

  async loginWithLine(code, redirectUri) {
    const profile = await this.exchangeLineCode(code, redirectUri);
    return this.loginOrRegisterWithSocial({
      provider: SOCIAL_PROVIDERS.LINE,
      providerUserId: profile.providerUserId,
      email: profile.email,
      name: profile.name,
    });
  }

  async loginOrRegisterWithSocial({
    provider,
    providerUserId,
    email,
    name,
    providerTokens = null,
  }) {
    const normalizedEmail = email?.trim().toLowerCase() || null;
    const requiresEmail = provider === SOCIAL_PROVIDERS.GOOGLE;

    if (!providerUserId) {
      throw new AppError('Social provider user id is required', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }

    const existingLink = await this.socialAccountRepository.findByProviderUserId(
      provider,
      providerUserId,
    );
    if (existingLink) {
      if (providerTokens) {
        await this.socialAccountRepository.updateProviderTokens({
          provider,
          providerUserId,
          accessToken: providerTokens.accessToken,
          refreshToken: providerTokens.refreshToken,
          tokenExpiresAt: providerTokens.tokenExpiresAt,
        });
      }
      return this._loginExistingUser(existingLink.user_id, provider);
    }

    if (requiresEmail && !normalizedEmail) {
      throw new AppError('Social account email is required', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }

    if (normalizedEmail) {
      const existingUser = await this.userRepository.findByEmail(normalizedEmail);
      if (existingUser) {
        if (existingUser.role !== ROLES.CUSTOMER) {
          throw new AppError('Invalid social login credentials', {
            statusCode: HTTP_STATUS.UNAUTHORIZED,
            errorCode: ERROR_CODES.AUTH_INVALID,
          });
        }
        await this.socialAccountRepository.create({
          userId: existingUser.id,
          provider,
          providerUserId,
          providerEmail: normalizedEmail,
          accessToken: providerTokens?.accessToken ?? null,
          refreshToken: providerTokens?.refreshToken ?? null,
          tokenExpiresAt: providerTokens?.tokenExpiresAt ?? null,
        });
        return this._loginExistingUser(existingUser.id, provider);
      }
    }

    const accountEmail = normalizedEmail
      || buildSocialPlaceholderEmail(provider, providerUserId);
    const displayName = name
      || normalizedEmail?.split('@')[0]
      || 'Customer';

    try {
      const user = await this.userRepository.createSocialCustomerWithProfile({
        email: accountEmail,
        displayName,
      });
      await this.socialAccountRepository.create({
        userId: user.id,
        provider,
        providerUserId,
        providerEmail: normalizedEmail,
        accessToken: providerTokens?.accessToken ?? null,
        refreshToken: providerTokens?.refreshToken ?? null,
        tokenExpiresAt: providerTokens?.tokenExpiresAt ?? null,
      });
      await this.userRepository.updateLastLoginAt(user.id);
      return this.authService.buildAuthResponse(user, provider);
    } catch (err) {
      if (err.code === 'ER_DUP_ENTRY') {
        throw new AppError('Email already registered', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.DUPLICATE_BOOKING,
        });
      }
      throw err;
    }
  }

  async _loginExistingUser(userId, provider = SOCIAL_PROVIDERS.GOOGLE) {
    const user = await this.userRepository.findById(userId);
    if (!user || !user.is_active || user.role !== ROLES.CUSTOMER) {
      const message = provider === SOCIAL_PROVIDERS.GOOGLE
        ? 'Invalid Google ID token'
        : 'Invalid social login credentials';
      throw new AppError(message, {
        statusCode: HTTP_STATUS.UNAUTHORIZED,
        errorCode: ERROR_CODES.AUTH_INVALID,
      });
    }

    await this.userRepository.updateLastLoginAt(user.id);
    return this.authService.buildAuthResponse(user, provider);
  }
}

module.exports = SocialAuthService;
module.exports.normalizeGoogleIdTokenPayload = normalizeGoogleIdTokenPayload;
module.exports.normalizeKakaoUserPayload = normalizeKakaoUserPayload;
module.exports.buildKakaoPlaceholderEmail = buildKakaoPlaceholderEmail;
module.exports.computeTokenExpiresAt = computeTokenExpiresAt;
module.exports.buildLinePlaceholderEmail = buildLinePlaceholderEmail;
module.exports.buildSocialPlaceholderEmail = buildSocialPlaceholderEmail;
module.exports.buildAuthorizationCodePrefix = buildAuthorizationCodePrefix;
module.exports.buildKakaoAuthorizationCodePrefix = buildKakaoAuthorizationCodePrefix;
module.exports.buildKakaoTokenExchangeFailureLogContext = buildKakaoTokenExchangeFailureLogContext;
module.exports.buildKakaoUserMeFailureLogContext = buildKakaoUserMeFailureLogContext;
module.exports.buildLineTokenExchangeFailureLogContext = buildLineTokenExchangeFailureLogContext;
module.exports.buildLineVerifyFailureLogContext = buildLineVerifyFailureLogContext;
module.exports.normalizeLineIdTokenPayload = normalizeLineIdTokenPayload;

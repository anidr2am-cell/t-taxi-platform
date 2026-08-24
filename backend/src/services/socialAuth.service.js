const { OAuth2Client } = require('google-auth-library');
const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const ROLES = require('../constants/roles');
const SOCIAL_PROVIDERS = require('../constants/socialProviders');

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

class SocialAuthService {
  constructor(userRepository, socialAccountRepository, authService, options = {}) {
    this.userRepository = userRepository;
    this.socialAccountRepository = socialAccountRepository;
    this.authService = authService;
    this.googleClientId = options.googleClientId || null;
    this.verifyGoogleIdTokenImpl = options.verifyGoogleIdTokenImpl || null;
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

  async loginWithGoogle(idToken) {
    const profile = await this.verifyGoogleIdToken(idToken);
    return this.loginOrRegisterWithSocial({
      provider: SOCIAL_PROVIDERS.GOOGLE,
      providerUserId: profile.providerUserId,
      email: profile.email,
      name: profile.name,
    });
  }

  async loginOrRegisterWithSocial({ provider, providerUserId, email, name }) {
    const normalizedEmail = email?.trim().toLowerCase() || null;
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
      return this._loginExistingUser(existingLink.user_id);
    }

    if (!normalizedEmail) {
      throw new AppError('Social account email is required', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }

    const existingUser = await this.userRepository.findByEmail(normalizedEmail);
    if (existingUser) {
      if (existingUser.role !== ROLES.CUSTOMER) {
        throw new AppError('Invalid Google ID token', {
          statusCode: HTTP_STATUS.UNAUTHORIZED,
          errorCode: ERROR_CODES.AUTH_INVALID,
        });
      }
      await this.socialAccountRepository.create({
        userId: existingUser.id,
        provider,
        providerUserId,
        providerEmail: normalizedEmail,
      });
      return this._loginExistingUser(existingUser.id);
    }

    try {
      const user = await this.userRepository.createSocialCustomerWithProfile({
        email: normalizedEmail,
        displayName: name || normalizedEmail.split('@')[0],
      });
      await this.socialAccountRepository.create({
        userId: user.id,
        provider,
        providerUserId,
        providerEmail: normalizedEmail,
      });
      await this.userRepository.updateLastLoginAt(user.id);
      return this.authService.buildAuthResponse(user);
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

  async _loginExistingUser(userId) {
    const user = await this.userRepository.findById(userId);
    if (!user || !user.is_active || user.role !== ROLES.CUSTOMER) {
      throw new AppError('Invalid Google ID token', {
        statusCode: HTTP_STATUS.UNAUTHORIZED,
        errorCode: ERROR_CODES.AUTH_INVALID,
      });
    }

    await this.userRepository.updateLastLoginAt(user.id);
    return this.authService.buildAuthResponse(user);
  }
}

module.exports = SocialAuthService;
module.exports.normalizeGoogleIdTokenPayload = normalizeGoogleIdTokenPayload;

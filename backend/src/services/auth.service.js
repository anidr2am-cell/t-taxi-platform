const bcrypt = require('bcryptjs');
const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const ROLES = require('../constants/roles');

const LOGIN_ALLOWED_ROLES = [
  ROLES.CUSTOMER,
  ROLES.ADMIN,
  ROLES.SUPER_ADMIN,
  ROLES.DRIVER,
];

class AuthService {
  constructor(userRepository, tokenService) {
    this.userRepository = userRepository;
    this.tokenService = tokenService;
  }

  mapUser(user) {
    return {
      id: user.id,
      email: user.email,
      role: user.role,
      name: user.name || null,
      phone: user.phone || null,
      locale: user.locale,
      isActive: Boolean(user.is_active),
    };
  }

  buildAuthResponse(user) {
    const accessToken = this.tokenService.signAccessToken(user);
    const { token: refreshToken } = this.tokenService.signRefreshToken(user);

    return {
      user: this.mapUser(user),
      accessToken,
      refreshToken,
      expiresIn: this.tokenService.getAccessExpiresInSeconds(),
    };
  }

  async register(input) {
    const email = input.email.trim().toLowerCase();
    const existing = await this.userRepository.findByEmail(email);
    if (existing) {
      throw new AppError('Email already registered', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.DUPLICATE_BOOKING,
      });
    }

    const passwordHash = await bcrypt.hash(input.password, 12);

    try {
      const user = await this.userRepository.createCustomerWithProfile({
        email,
        passwordHash,
        phone: input.phone,
        phoneCountryCode: input.phoneCountryCode || null,
        countryCode: input.countryCode || null,
        locale: input.locale || 'ko',
        displayName: input.name,
      });

      return this.buildAuthResponse(user);
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

  async login(input) {
    const email = input.email.trim().toLowerCase();
    const user = await this.userRepository.findByEmail(email);

    if (!user || !user.password_hash) {
      throw new AppError('Invalid email or password', {
        statusCode: HTTP_STATUS.UNAUTHORIZED,
        errorCode: ERROR_CODES.AUTH_INVALID,
      });
    }

    if (!LOGIN_ALLOWED_ROLES.includes(user.role)) {
      throw new AppError('Invalid email or password', {
        statusCode: HTTP_STATUS.UNAUTHORIZED,
        errorCode: ERROR_CODES.AUTH_INVALID,
      });
    }

    if (!user.is_active) {
      throw new AppError('Account is disabled', {
        statusCode: HTTP_STATUS.UNAUTHORIZED,
        errorCode: ERROR_CODES.AUTH_INVALID,
      });
    }

    const valid = await bcrypt.compare(input.password, user.password_hash);
    if (!valid) {
      throw new AppError('Invalid email or password', {
        statusCode: HTTP_STATUS.UNAUTHORIZED,
        errorCode: ERROR_CODES.AUTH_INVALID,
      });
    }

    await this.userRepository.updateLastLoginAt(user.id);
    return this.buildAuthResponse(user);
  }

  async refresh(refreshToken) {
    try {
      const payload = this.tokenService.verifyRefreshToken(refreshToken);
      const user = await this.userRepository.findById(payload.userId);

      if (!user || !user.is_active) {
        throw new AppError('Invalid refresh token', {
          statusCode: HTTP_STATUS.UNAUTHORIZED,
          errorCode: ERROR_CODES.AUTH_INVALID,
        });
      }

      return {
        accessToken: this.tokenService.signAccessToken(user),
        expiresIn: this.tokenService.getAccessExpiresInSeconds(),
      };
    } catch (err) {
      if (err instanceof AppError) {
        throw err;
      }
      throw new AppError('Invalid refresh token', {
        statusCode: HTTP_STATUS.UNAUTHORIZED,
        errorCode: ERROR_CODES.AUTH_INVALID,
      });
    }
  }

  async logout(refreshToken) {
    if (!refreshToken) {
      return;
    }

    try {
      const payload = this.tokenService.verifyRefreshToken(refreshToken);
      this.tokenService.revokeRefreshToken(payload.jti, payload.exp);
    } catch {
      // Logout is idempotent when token is already invalid.
    }
  }

  async getMe(userId) {
    const user = await this.userRepository.findById(userId);
    if (!user || !user.is_active) {
      throw new AppError('User not found', {
        statusCode: HTTP_STATUS.UNAUTHORIZED,
        errorCode: ERROR_CODES.UNAUTHORIZED,
      });
    }
    return this.mapUser(user);
  }

  verifyAccessToken(token) {
    try {
      return this.tokenService.verifyAccessToken(token);
    } catch {
      throw new AppError('Invalid or expired token', {
        statusCode: HTTP_STATUS.UNAUTHORIZED,
        errorCode: ERROR_CODES.UNAUTHORIZED,
      });
    }
  }
}

module.exports = AuthService;

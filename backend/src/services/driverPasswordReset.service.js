const crypto = require('node:crypto');
const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const { hashPassword, verifyPassword } = require('../utils/passwordHash.util');
const config = require('../config');
const logger = require('../utils/logger');
const { thaiMobileNumber } = require('../utils/driverResetIdentifier.util');

const CODE_TTL_MS = 10 * 60 * 1000;
const MAX_ATTEMPTS = 5;

class DriverPasswordResetService {
  constructor(userRepository, resetRepository, emailService, options = {}) {
    this.userRepository = userRepository;
    this.resetRepository = resetRepository;
    this.emailService = emailService;
    this.now = options.now || (() => Date.now());
    this.randomInt = options.randomInt || crypto.randomInt;
    this.secret = options.secret || config.jwt.refreshSecret;
  }

  hashCode(userId, code) {
    return crypto.createHmac('sha256', this.secret).update(`${userId}:${code}`).digest('hex');
  }

  async findDriver(identifier) {
    const normalized = String(identifier || '').trim();
    if (!normalized) return null;
    const national = thaiMobileNumber(normalized);
    let user;
    if (normalized.includes('@')) {
      user = await this.userRepository.findByEmail(normalized.toLowerCase());
    } else if (national) {
      user = await this.userRepository.findUniqueDriverForReset([
        normalized, `0${national}`, `+66${national}`, `66${national}`, `0066${national}`,
      ]);
    } else {
      user = await this.userRepository.findDriverByPhone(normalized);
    }
    return user?.role === 'DRIVER' && user.is_active ? user : null;
  }

  async requestCode(identifier) {
    const user = await this.findDriver(identifier);
    const email = user?.email?.trim();
    if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || /\.local$/i.test(email)) return;
    const code = String(this.randomInt(100000, 1000000));
    await this.resetRepository.createCode({
      userId: user.id,
      codeHash: this.hashCode(user.id, code),
      expiresAt: new Date(this.now() + CODE_TTL_MS),
    });
    try {
      await this.emailService.sendCode({ email, code, locale: user.locale });
    } catch (err) {
      logger.error('Driver password reset email delivery failed', {
        driverUserId: user.id,
        errorCode: err.code || err.message,
      });
    }
  }

  async resetPassword({ identifier, code, newPassword }) {
    const user = await this.findDriver(identifier);
    if (!user) this.throwInvalidCode();
    const passwordHash = await hashPassword(newPassword);
    const updated = await this.resetRepository.consumeCodeAndUpdatePassword({
      userId: user.id,
      codeHash: this.hashCode(user.id, code),
      passwordHash,
      maxAttempts: MAX_ATTEMPTS,
    });
    if (!updated) this.throwInvalidCode();
  }

  async changePassword(userId, currentPassword, newPassword) {
    const user = await this.userRepository.findById(userId);
    if (user?.role !== 'DRIVER' || !user.is_active || !user.password_hash
        || !(await verifyPassword(currentPassword, user.password_hash))) {
      throw new AppError('Current password is incorrect', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.CURRENT_PASSWORD_INCORRECT,
      });
    }
    if (await verifyPassword(newPassword, user.password_hash)) {
      throw new AppError('New password must differ from current password', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.PASSWORD_UNCHANGED,
      });
    }

    const updated = await this.resetRepository.changePassword({
      userId,
      currentHash: user.password_hash,
      passwordHash: await hashPassword(newPassword),
    });
    if (!updated) {
      throw new AppError('Password changed during the request', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.PASSWORD_CHANGE_CONFLICT,
      });
    }
  }

  throwInvalidCode() {
    throw new AppError('Invalid or expired verification code', {
      statusCode: HTTP_STATUS.BAD_REQUEST,
      errorCode: ERROR_CODES.PASSWORD_RESET_CODE_INVALID,
    });
  }
}

module.exports = DriverPasswordResetService;

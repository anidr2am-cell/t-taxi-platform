const crypto = require('node:crypto');
const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const { hashPassword } = require('../utils/passwordHash.util');
const config = require('../config');
const logger = require('../utils/logger');

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
    const user = normalized.includes('@')
      ? await this.userRepository.findByEmail(normalized.toLowerCase())
      : await this.userRepository.findDriverByPhone(normalized);
    return user?.role === 'DRIVER' && user.is_active ? user : null;
  }

  async requestCode(identifier) {
    const user = await this.findDriver(identifier);
    if (!user?.email) return;
    const code = String(this.randomInt(100000, 1000000));
    await this.resetRepository.createCode({
      userId: user.id,
      codeHash: this.hashCode(user.id, code),
      expiresAt: new Date(this.now() + CODE_TTL_MS),
    });
    try {
      await this.emailService.sendCode({ email: user.email, code, locale: user.locale });
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

  throwInvalidCode() {
    throw new AppError('Invalid or expired verification code', {
      statusCode: HTTP_STATUS.BAD_REQUEST,
      errorCode: ERROR_CODES.PASSWORD_RESET_CODE_INVALID,
    });
  }
}

module.exports = DriverPasswordResetService;

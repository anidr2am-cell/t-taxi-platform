const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const ROLES = require('../constants/roles');
const { isDuplicatePhoneEntry } = require('../utils/duplicateEntry.util');

class CustomerProfileService {
  constructor(pool, userRepository) {
    this.pool = pool;
    this.userRepository = userRepository;
  }

  validation(message, field) {
    throw new AppError(message, {
      statusCode: HTTP_STATUS.BAD_REQUEST,
      errorCode: ERROR_CODES.VALIDATION_ERROR,
      errors: field ? [{ field, message }] : undefined,
    });
  }

  notFound() {
    throw new AppError('Customer not found', {
      statusCode: HTTP_STATUS.NOT_FOUND,
      errorCode: ERROR_CODES.CUSTOMER_NOT_FOUND,
    });
  }

  duplicatePhoneConflict() {
    const message = '이미 다른 계정에서 사용 중인 전화번호입니다';
    throw new AppError(message, {
      statusCode: HTTP_STATUS.CONFLICT,
      errorCode: ERROR_CODES.DUPLICATE_BOOKING,
      errors: [{ field: 'phone', message }],
    });
  }

  normalizeName(name) {
    const value = String(name ?? '').trim();
    if (!value) {
      this.validation('Name is required', 'name');
    }
    if (value.length > 100) {
      this.validation('Name is too long', 'name');
    }
    return value;
  }

  normalizePhone(phone) {
    const value = String(phone ?? '').trim();
    if (!value) {
      this.validation('Phone number is required', 'phone');
    }
    return value;
  }

  normalizePhoneCountryCode(code) {
    if (code == null || code === '') {
      return null;
    }
    return String(code).trim() || null;
  }

  mapProfile(user) {
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

  async updateProfile(customerUserId, input) {
    const name = this.normalizeName(input.name);
    const phone = this.normalizePhone(input.phone);
    const phoneCountryCode = this.normalizePhoneCountryCode(input.phoneCountryCode);

    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      const row = await this.userRepository.findByIdForUpdate(conn, customerUserId);
      if (!row || row.role !== ROLES.CUSTOMER) {
        this.notFound();
      }

      await this.userRepository.updateCustomerProfile(conn, {
        userId: customerUserId,
        name,
        phone,
        phoneCountryCode,
      });

      await conn.commit();
    } catch (err) {
      await conn.rollback();
      if (isDuplicatePhoneEntry(err)) {
        this.duplicatePhoneConflict();
      }
      throw err;
    } finally {
      conn.release();
    }

    const updated = await this.userRepository.findById(customerUserId);
    return this.mapProfile(updated);
  }
}

module.exports = CustomerProfileService;

const fs = require('fs/promises');
const path = require('path');
const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const COUPON_STATUS = require('../constants/couponStatus');
const CHARGE_TYPES = require('../constants/chargeTypes');
const { uploadDir } = require('../config/multer');
const { formatServiceDateTimeForApi } = require('../utils/serviceDateTime.util');
const {
  customerCouponImageUrl,
  adminCouponTemplateImageUrl,
} = require('../utils/couponAssetUrl');
const {
  detectImageFileSignature,
  isSupportedSettingsImageMetadata,
} = require('../utils/imageSignature');

class CouponService {
  constructor(couponRepository, pool, couponTemplateRepository = null) {
    this.couponRepository = couponRepository;
    this.pool = pool;
    this.couponTemplateRepository = couponTemplateRepository;
  }

  mapCouponRow(row) {
    return {
      id: Number(row.id),
      title: row.title,
      discountAmount: Number(row.discount_amount),
      status: row.status,
      issuedAt: formatServiceDateTimeForApi(row.issued_at),
      usedAt: row.used_at ? formatServiceDateTimeForApi(row.used_at) : null,
      usedBookingId: row.used_booking_id != null ? Number(row.used_booking_id) : null,
      bookingNumber: row.booking_number ?? null,
      templateId: row.template_id != null ? Number(row.template_id) : null,
      imageUrl: row.image_path ? customerCouponImageUrl(row.id) : null,
    };
  }

  mapAdminCouponRow(row) {
    return {
      id: Number(row.id),
      title: row.title,
      discountAmount: Number(row.discount_amount),
      status: row.status,
      issuedAt: formatServiceDateTimeForApi(row.issued_at),
      usedAt: row.used_at ? formatServiceDateTimeForApi(row.used_at) : null,
      customer: {
        id: Number(row.customer_user_id),
        name: row.customer_name ?? null,
        email: row.customer_email ?? null,
        phone: row.customer_phone ?? null,
      },
    };
  }

  mapTemplateRow(row) {
    return {
      id: Number(row.id),
      title: row.title,
      discountAmount: Number(row.discount_amount),
      isActive: Boolean(row.is_active),
      imageUrl: adminCouponTemplateImageUrl(row.id),
      createdAt: formatServiceDateTimeForApi(row.created_at),
      updatedAt: formatServiceDateTimeForApi(row.updated_at),
    };
  }

  mapRecentCustomerRow(row) {
    return {
      id: Number(row.id),
      name: row.name ?? null,
      phone: row.phone ?? null,
      email: row.email ?? null,
      lastCompletedAt: row.last_completed_at
        ? formatServiceDateTimeForApi(row.last_completed_at)
        : null,
    };
  }

  async searchCustomers(query) {
    const rows = await this.couponRepository.searchCustomers(query);
    return rows.map((row) => ({
      id: Number(row.id),
      name: row.name ?? null,
      phone: row.phone ?? null,
      email: row.email ?? null,
    }));
  }

  async listRecentCompletedCustomers(limit = 20) {
    const rows = await this.couponRepository.listRecentCompletedCustomers(limit);
    return rows.map((row) => this.mapRecentCustomerRow(row));
  }

  invalidTemplateImage() {
    return new AppError('Only PNG and JPEG images are supported', {
      statusCode: HTTP_STATUS.BAD_REQUEST,
      errorCode: ERROR_CODES.INVALID_SETTINGS_IMAGE,
    });
  }

  async cleanupUploadedFile(file) {
    if (!file?.path) return;
    try {
      await fs.unlink(file.path);
    } catch (_) {
      // ignore cleanup failures
    }
  }

  async saveTemplateImage(file) {
    if (!file) {
      throw this.invalidTemplateImage();
    }
    let detectedType = null;
    try {
      detectedType = await detectImageFileSignature(file.path);
    } catch (_) {
      await this.cleanupUploadedFile(file);
      throw this.invalidTemplateImage();
    }
    if (!isSupportedSettingsImageMetadata(file, detectedType)) {
      await this.cleanupUploadedFile(file);
      throw this.invalidTemplateImage();
    }
    return path.relative(uploadDir, file.path).replace(/\\/g, '/');
  }

  async createTemplate({ title, discountAmount, file, createdByAdminId = null }) {
    if (!this.couponTemplateRepository) {
      throw new AppError('Coupon template service is unavailable', {
        statusCode: HTTP_STATUS.INTERNAL_SERVER_ERROR,
        errorCode: ERROR_CODES.INTERNAL_SERVER_ERROR,
      });
    }

    const imagePath = await this.saveTemplateImage(file);
    const templateId = await this.couponTemplateRepository.insertTemplate({
      title: title.trim(),
      discountAmount,
      imagePath,
      createdByAdminId,
    });
    const template = await this.couponTemplateRepository.findById(templateId);
    return this.mapTemplateRow(template);
  }

  async listTemplates() {
    if (!this.couponTemplateRepository) return [];
    const rows = await this.couponTemplateRepository.listAll();
    return rows.map((row) => this.mapTemplateRow(row));
  }

  async setTemplateActive(templateId, isActive) {
    if (!this.couponTemplateRepository) {
      throw new AppError('Coupon template service is unavailable', {
        statusCode: HTTP_STATUS.INTERNAL_SERVER_ERROR,
        errorCode: ERROR_CODES.INTERNAL_SERVER_ERROR,
      });
    }

    const template = await this.couponTemplateRepository.findById(templateId);
    if (!template) {
      throw new AppError('Coupon template not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.COUPON_TEMPLATE_NOT_FOUND,
      });
    }

    const affected = await this.couponTemplateRepository.updateIsActive(templateId, isActive);
    if (affected === 0) {
      throw new AppError('Coupon template not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.COUPON_TEMPLATE_NOT_FOUND,
      });
    }

    const updated = await this.couponTemplateRepository.findById(templateId);
    return this.mapTemplateRow(updated);
  }

  resolveTemplateImageAbsolutePath(relativePath) {
    if (!relativePath) {
      throw new AppError('File not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.FILE_NOT_FOUND,
      });
    }
    const absolutePath = path.resolve(uploadDir, String(relativePath));
    const root = `${path.resolve(uploadDir)}${path.sep}`;
    if (absolutePath !== path.resolve(uploadDir) && !absolutePath.startsWith(root)) {
      throw new AppError('Invalid file path', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.FILE_NOT_FOUND,
      });
    }
    return absolutePath;
  }

  async getTemplateImagePath(templateId) {
    if (!this.couponTemplateRepository) {
      throw new AppError('Coupon template not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.COUPON_TEMPLATE_NOT_FOUND,
      });
    }
    const template = await this.couponTemplateRepository.findById(templateId);
    if (!template?.image_path) {
      throw new AppError('File not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.FILE_NOT_FOUND,
      });
    }
    return this.resolveTemplateImageAbsolutePath(template.image_path);
  }

  async getCustomerCouponImagePath(couponId, customerUserId) {
    const coupon = await this.couponRepository.findOwnedById(couponId, customerUserId);
    if (!coupon) {
      throw new AppError('Coupon not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.COUPON_NOT_FOUND,
      });
    }
    if (!coupon.image_path) {
      throw new AppError('File not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.FILE_NOT_FOUND,
      });
    }
    return this.resolveTemplateImageAbsolutePath(coupon.image_path);
  }

  async issueCoupon({
    customerUserId,
    title,
    discountAmount,
    templateId = null,
    issuedByAdminId = null,
  }) {
    const customer = await this.couponRepository.findCustomerById(customerUserId);
    if (!customer) {
      throw new AppError('Customer not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.CUSTOMER_NOT_FOUND,
      });
    }

    let resolvedTitle = title?.trim() ?? '';
    let resolvedDiscountAmount = discountAmount;
    let resolvedTemplateId = null;
    let imagePath = null;

    if (templateId != null) {
      if (!this.couponTemplateRepository) {
        throw new AppError('Coupon template not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.COUPON_TEMPLATE_NOT_FOUND,
        });
      }
      const template = await this.couponTemplateRepository.findById(templateId);
      if (!template) {
        throw new AppError('Coupon template not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.COUPON_TEMPLATE_NOT_FOUND,
        });
      }
      resolvedTitle = template.title;
      resolvedDiscountAmount = Number(template.discount_amount);
      resolvedTemplateId = Number(template.id);
      imagePath = template.image_path;
    }

    if (!resolvedTitle || !Number.isFinite(Number(resolvedDiscountAmount)) || resolvedDiscountAmount <= 0) {
      throw new AppError('Invalid coupon payload', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }

    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      const couponId = await this.couponRepository.insertCoupon(conn, {
        customerUserId,
        title: resolvedTitle,
        discountAmount: resolvedDiscountAmount,
        templateId: resolvedTemplateId,
        imagePath,
        issuedByAdminId,
      });
      await conn.commit();
      const coupon = await this.couponRepository.findById(couponId);
      return this.mapCouponRow(coupon);
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }

  async cancelCoupon(couponId) {
    const coupon = await this.couponRepository.findById(couponId);
    if (!coupon) {
      throw new AppError('Coupon not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.COUPON_NOT_FOUND,
      });
    }

    if (coupon.status === COUPON_STATUS.USED) {
      throw new AppError('Coupon has already been used', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.COUPON_ALREADY_USED,
      });
    }

    const affected = await this.couponRepository.deleteAvailable(couponId);
    if (affected === 0) {
      throw new AppError('Coupon not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.COUPON_NOT_FOUND,
      });
    }
  }

  async listCouponsForCustomer(customerUserId) {
    const rows = await this.couponRepository.listByCustomerUserId(customerUserId);
    return rows.map((row) => this.mapCouponRow(row));
  }

  async listRecentIssued(limit = 20) {
    const rows = await this.couponRepository.listRecentIssued(limit);
    return rows.map((row) => this.mapAdminCouponRow(row));
  }

  assertCouponAuthRequired(couponId, authUser) {
    if (couponId == null) return;
    if (!authUser) {
      throw new AppError('Login is required to use a coupon', {
        statusCode: HTTP_STATUS.UNAUTHORIZED,
        errorCode: ERROR_CODES.COUPON_AUTH_REQUIRED,
      });
    }
  }

  async resolveAvailableCoupon(conn, couponId, customerUserId) {
    const coupon = await this.couponRepository.findAvailableForCustomer(
      conn,
      couponId,
      customerUserId,
    );
    if (!coupon) {
      throw new AppError('Invalid or unavailable coupon', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.COUPON_NOT_AVAILABLE,
      });
    }
    return coupon;
  }

  buildCouponChargeItem(coupon, subtotal) {
    const normalizedSubtotal = Number(subtotal);
    const discountCap = Number.isFinite(normalizedSubtotal) && normalizedSubtotal > 0
      ? normalizedSubtotal
      : 0;
    const appliedDiscount = Math.min(Number(coupon.discount_amount), discountCap);
    if (appliedDiscount <= 0) {
      return null;
    }

    return {
      chargeType: CHARGE_TYPES.COUPON,
      description: coupon.title,
      quantity: 1,
      unitPrice: -appliedDiscount,
      amount: -appliedDiscount,
      referenceType: 'COUPON',
      referenceId: coupon.id,
    };
  }

  async markCouponUsed(conn, couponId, bookingId, customerUserId) {
    const affected = await this.couponRepository.markUsed(
      conn,
      couponId,
      bookingId,
      customerUserId,
    );
    if (affected === 0) {
      throw new AppError('이미 사용됐거나 유효하지 않은 쿠폰입니다', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.COUPON_NOT_AVAILABLE,
      });
    }
  }
}

module.exports = CouponService;

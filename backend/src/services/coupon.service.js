const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const COUPON_STATUS = require('../constants/couponStatus');
const CHARGE_TYPES = require('../constants/chargeTypes');
const { formatServiceDateTimeForApi } = require('../utils/serviceDateTime.util');

class CouponService {
  constructor(couponRepository, pool) {
    this.couponRepository = couponRepository;
    this.pool = pool;
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

  async searchCustomers(query) {
    const rows = await this.couponRepository.searchCustomers(query);
    return rows.map((row) => ({
      id: Number(row.id),
      name: row.name ?? null,
      phone: row.phone ?? null,
      email: row.email ?? null,
    }));
  }

  async issueCoupon({ customerUserId, title, discountAmount, issuedByAdminId = null }) {
    const customer = await this.couponRepository.findCustomerById(customerUserId);
    if (!customer) {
      throw new AppError('Customer not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.CUSTOMER_NOT_FOUND,
      });
    }

    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      const couponId = await this.couponRepository.insertCoupon(conn, {
        customerUserId,
        title: title.trim(),
        discountAmount,
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

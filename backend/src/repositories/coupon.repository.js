const database = require('../config/database');
const COUPON_STATUS = require('../constants/couponStatus');

class CouponRepository {
  constructor(pool = database.pool) {
    this.pool = pool;
  }

  async searchCustomers(query, limit = 20) {
    const trimmed = String(query ?? '').trim();
    if (!trimmed) return [];

    const pattern = `%${trimmed}%`;
    const safeLimit = Math.min(Math.max(Number(limit) || 20, 1), 50);

    const [rows] = await this.pool.query(
      `
        SELECT
          u.id,
          u.email,
          u.phone,
          up.display_name AS name
        FROM users u
        LEFT JOIN user_profiles up
          ON up.user_id = u.id AND up.deleted_at IS NULL
        WHERE u.role = 'CUSTOMER'
          AND u.deleted_at IS NULL
          AND u.is_active = 1
          AND (
            u.email LIKE ?
            OR u.phone LIKE ?
            OR up.display_name LIKE ?
          )
        ORDER BY u.id DESC
        LIMIT ?
      `,
      [pattern, pattern, pattern, safeLimit],
    );
    return rows;
  }

  async findCustomerById(customerUserId) {
    const [rows] = await this.pool.query(
      `
        SELECT
          u.id,
          u.email,
          u.phone,
          u.role,
          up.display_name AS name
        FROM users u
        LEFT JOIN user_profiles up
          ON up.user_id = u.id AND up.deleted_at IS NULL
        WHERE u.id = ?
          AND u.role = 'CUSTOMER'
          AND u.deleted_at IS NULL
          AND u.is_active = 1
        LIMIT 1
      `,
      [customerUserId],
    );
    return rows[0] || null;
  }

  async insertCoupon(conn, {
    customerUserId,
    title,
    discountAmount,
    templateId = null,
    imagePath = null,
    issuedByAdminId = null,
  }) {
    const [result] = await conn.query(
      `
        INSERT INTO customer_coupons (
          customer_user_id,
          title,
          discount_amount,
          template_id,
          image_path,
          status,
          issued_by_admin_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
      `,
      [
        customerUserId,
        title,
        discountAmount,
        templateId,
        imagePath,
        COUPON_STATUS.AVAILABLE,
        issuedByAdminId,
      ],
    );
    return result.insertId;
  }

  async findById(couponId, conn = this.pool) {
    const [rows] = await conn.query(
      `
        SELECT
          id,
          customer_user_id,
          title,
          discount_amount,
          template_id,
          image_path,
          status,
          issued_by_admin_id,
          issued_at,
          used_at,
          used_booking_id,
          created_at,
          updated_at
        FROM customer_coupons
        WHERE id = ?
        LIMIT 1
      `,
      [couponId],
    );
    return rows[0] || null;
  }

  async findAvailableForCustomer(conn, couponId, customerUserId) {
    const [rows] = await conn.query(
      `
        SELECT
          id,
          customer_user_id,
          title,
          discount_amount,
          template_id,
          image_path,
          status,
          issued_by_admin_id,
          issued_at,
          used_at,
          used_booking_id
        FROM customer_coupons
        WHERE id = ?
          AND customer_user_id = ?
          AND status = ?
        LIMIT 1
      `,
      [couponId, customerUserId, COUPON_STATUS.AVAILABLE],
    );
    return rows[0] || null;
  }

  async listByCustomerUserId(customerUserId) {
    const [rows] = await this.pool.query(
      `
        SELECT
          cc.id,
          cc.title,
          cc.discount_amount,
          cc.template_id,
          cc.image_path,
          cc.status,
          cc.issued_at,
          cc.used_at,
          cc.used_booking_id,
          b.booking_number
        FROM customer_coupons cc
        LEFT JOIN bookings b
          ON b.id = cc.used_booking_id AND b.deleted_at IS NULL
        WHERE cc.customer_user_id = ?
        ORDER BY
          CASE cc.status WHEN 'AVAILABLE' THEN 0 ELSE 1 END,
          cc.issued_at DESC,
          cc.id DESC
      `,
      [customerUserId],
    );
    return rows;
  }

  async listRecentIssued(limit = 20) {
    const safeLimit = Math.min(Math.max(Number(limit) || 20, 1), 100);
    const [rows] = await this.pool.query(
      `
        SELECT
          cc.id,
          cc.title,
          cc.discount_amount,
          cc.status,
          cc.issued_at,
          cc.used_at,
          cc.customer_user_id,
          up.display_name AS customer_name,
          u.email AS customer_email,
          u.phone AS customer_phone
        FROM customer_coupons cc
        INNER JOIN users u
          ON u.id = cc.customer_user_id AND u.deleted_at IS NULL
        LEFT JOIN user_profiles up
          ON up.user_id = u.id AND up.deleted_at IS NULL
        ORDER BY cc.issued_at DESC, cc.id DESC
        LIMIT ?
      `,
      [safeLimit],
    );
    return rows;
  }

  async deleteAvailable(couponId) {
    const [result] = await this.pool.query(
      `
        DELETE FROM customer_coupons
        WHERE id = ?
          AND status = ?
      `,
      [couponId, COUPON_STATUS.AVAILABLE],
    );
    return result.affectedRows;
  }

  async markUsed(conn, couponId, bookingId, customerUserId) {
    const [result] = await conn.query(
      `
        UPDATE customer_coupons
        SET
          status = ?,
          used_at = CURRENT_TIMESTAMP,
          used_booking_id = ?,
          updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
          AND customer_user_id = ?
          AND status = ?
      `,
      [
        COUPON_STATUS.USED,
        bookingId,
        couponId,
        customerUserId,
        COUPON_STATUS.AVAILABLE,
      ],
    );
    return result.affectedRows;
  }

  async findOwnedById(couponId, customerUserId) {
    const [rows] = await this.pool.query(
      `
        SELECT
          id,
          customer_user_id,
          title,
          discount_amount,
          template_id,
          image_path,
          status,
          issued_by_admin_id,
          issued_at,
          used_at,
          used_booking_id
        FROM customer_coupons
        WHERE id = ?
          AND customer_user_id = ?
        LIMIT 1
      `,
      [couponId, customerUserId],
    );
    return rows[0] || null;
  }

  async listRecentCompletedCustomers(limit = 20) {
    const safeLimit = Math.min(Math.max(Number(limit) || 20, 1), 50);
    const [rows] = await this.pool.query(
      `
        SELECT
          b.customer_user_id AS id,
          u.email,
          u.phone,
          up.display_name AS name,
          MAX(b.completed_at) AS last_completed_at
        FROM bookings b
        INNER JOIN users u
          ON u.id = b.customer_user_id
          AND u.deleted_at IS NULL
          AND u.is_active = 1
        LEFT JOIN user_profiles up
          ON up.user_id = u.id AND up.deleted_at IS NULL
        WHERE b.status = 'COMPLETED'
          AND b.deleted_at IS NULL
          AND b.customer_user_id IS NOT NULL
          AND u.role = 'CUSTOMER'
        GROUP BY b.customer_user_id, u.email, u.phone, up.display_name
        ORDER BY last_completed_at DESC
        LIMIT ?
      `,
      [safeLimit],
    );
    return rows;
  }
}

module.exports = CouponRepository;

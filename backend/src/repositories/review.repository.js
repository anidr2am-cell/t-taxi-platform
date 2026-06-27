const database = require('../config/database');

class ReviewRepository {
  constructor(pool = database.pool) {
    this.pool = pool;
  }

  async insert(conn, data) {
    const [result] = await conn.query(
      `
        INSERT INTO reviews (
          booking_id,
          driver_id,
          customer_user_id,
          guest_access_token_id,
          rating,
          comment,
          moderation_status
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
      `,
      [
        data.bookingId,
        data.driverId,
        data.customerUserId ?? null,
        data.guestAccessTokenId ?? null,
        data.rating,
        data.comment ?? null,
        data.moderationStatus ?? 'VISIBLE',
      ],
    );
    return result.insertId;
  }

  async findByBookingIdForUpdate(conn, bookingId) {
    const [rows] = await conn.query(
      `
        SELECT
          r.id,
          r.booking_id,
          r.driver_id,
          r.customer_user_id,
          r.guest_access_token_id,
          r.rating,
          r.comment,
          r.moderation_status,
          r.hidden_reason,
          r.reviewed_by,
          r.reviewed_at,
          r.created_at,
          r.updated_at,
          b.booking_number
        FROM reviews r
        INNER JOIN bookings b ON b.id = r.booking_id AND b.deleted_at IS NULL
        WHERE r.booking_id = ?
        LIMIT 1
        FOR UPDATE
      `,
      [bookingId],
    );
    return rows[0] || null;
  }

  async findByBookingId(bookingId) {
    const [rows] = await this.pool.query(
      `
        SELECT
          r.id,
          r.booking_id,
          r.driver_id,
          r.customer_user_id,
          r.guest_access_token_id,
          r.rating,
          r.comment,
          r.moderation_status,
          r.hidden_reason,
          r.reviewed_by,
          r.reviewed_at,
          r.created_at,
          r.updated_at,
          b.booking_number
        FROM reviews r
        INNER JOIN bookings b ON b.id = r.booking_id AND b.deleted_at IS NULL
        WHERE r.booking_id = ?
        LIMIT 1
      `,
      [bookingId],
    );
    return rows[0] || null;
  }

  async findById(reviewId) {
    const [rows] = await this.pool.query(
      `
        SELECT
          r.id,
          r.booking_id,
          r.driver_id,
          r.customer_user_id,
          r.guest_access_token_id,
          r.rating,
          r.comment,
          r.moderation_status,
          r.hidden_reason,
          r.reviewed_by,
          r.reviewed_at,
          r.created_at,
          r.updated_at,
          b.booking_number,
          b.status AS booking_status,
          b.completed_at,
          b.total_amount,
          b.currency,
          d.name AS driver_name,
          d.phone AS driver_phone,
          u.id AS customer_user_id_ref,
          up.display_name AS customer_name
        FROM reviews r
        INNER JOIN bookings b ON b.id = r.booking_id AND b.deleted_at IS NULL
        INNER JOIN drivers d ON d.id = r.driver_id AND d.deleted_at IS NULL
        LEFT JOIN users u ON u.id = r.customer_user_id AND u.deleted_at IS NULL
        LEFT JOIN user_profiles up ON up.user_id = u.id
        WHERE r.id = ?
        LIMIT 1
      `,
      [reviewId],
    );
    return rows[0] || null;
  }

  async findByIdForUpdate(conn, reviewId) {
    const [rows] = await conn.query(
      `
        SELECT
          r.id,
          r.booking_id,
          r.driver_id,
          r.rating,
          r.comment,
          r.moderation_status,
          r.hidden_reason,
          r.reviewed_by,
          r.reviewed_at,
          r.created_at,
          b.booking_number
        FROM reviews r
        INNER JOIN bookings b ON b.id = r.booking_id AND b.deleted_at IS NULL
        WHERE r.id = ?
        LIMIT 1
        FOR UPDATE
      `,
      [reviewId],
    );
    return rows[0] || null;
  }

  async updateModeration(conn, reviewId, fields) {
    const sets = [];
    const params = [];
    if (fields.moderationStatus !== undefined) {
      sets.push('moderation_status = ?');
      params.push(fields.moderationStatus);
    }
    if (fields.hiddenReason !== undefined) {
      sets.push('hidden_reason = ?');
      params.push(fields.hiddenReason);
    }
    if (fields.reviewedBy !== undefined) {
      sets.push('reviewed_by = ?');
      params.push(fields.reviewedBy);
    }
    if (fields.reviewedAt !== undefined) {
      sets.push('reviewed_at = ?');
      params.push(fields.reviewedAt);
    }
    if (!sets.length) return;
    params.push(reviewId);
    await conn.query(
      `
        UPDATE reviews
        SET ${sets.join(', ')}, updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
      `,
      params,
    );
  }

  async getVisibleRatingSummaryForDriver(driverId) {
    const [rows] = await this.pool.query(
      `
        SELECT
          COUNT(*) AS review_count,
          AVG(rating) AS average_rating
        FROM reviews
        WHERE driver_id = ?
          AND moderation_status = 'VISIBLE'
      `,
      [driverId],
    );
    const row = rows[0] || {};
    const count = Number(row.review_count ?? 0);
    if (!count) {
      return { averageRating: null, reviewCount: 0 };
    }
    const avg = Number(row.average_rating);
    return {
      averageRating: Math.round(avg * 10) / 10,
      reviewCount: count,
    };
  }

  buildAdminFilters(filters) {
    const where = ['1 = 1'];
    const params = [];

    if (filters.rating) {
      where.push('r.rating = ?');
      params.push(filters.rating);
    }
    if (filters.status) {
      where.push('r.moderation_status = ?');
      params.push(filters.status);
    }
    if (filters.driverId) {
      where.push('r.driver_id = ?');
      params.push(filters.driverId);
    }
    if (filters.bookingNumber) {
      where.push('b.booking_number = ?');
      params.push(filters.bookingNumber);
    }
    if (filters.search) {
      where.push('(b.booking_number LIKE ? OR d.name LIKE ? OR r.comment LIKE ?)');
      const term = `%${filters.search}%`;
      params.push(term, term, term);
    }
    if (filters.dateFrom) {
      where.push('r.created_at >= ?');
      params.push(filters.dateFrom);
    }
    if (filters.dateTo) {
      where.push('r.created_at < ?');
      params.push(filters.dateTo);
    }

    return { whereSql: where.join(' AND '), params };
  }

  async countAdminReviews(filters) {
    const { whereSql, params } = this.buildAdminFilters(filters);
    const [rows] = await this.pool.query(
      `
        SELECT COUNT(*) AS total
        FROM reviews r
        INNER JOIN bookings b ON b.id = r.booking_id AND b.deleted_at IS NULL
        INNER JOIN drivers d ON d.id = r.driver_id AND d.deleted_at IS NULL
        WHERE ${whereSql}
      `,
      params,
    );
    return Number(rows[0]?.total ?? 0);
  }

  async findAdminReviews(filters, pagination) {
    const { whereSql, params } = this.buildAdminFilters(filters);
    const [rows] = await this.pool.query(
      `
        SELECT
          r.id,
          r.booking_id,
          r.driver_id,
          r.customer_user_id,
          r.rating,
          r.comment,
          r.moderation_status,
          r.hidden_reason,
          r.created_at,
          b.booking_number,
          d.name AS driver_name,
          u.id AS customer_user_id_ref,
          up.display_name AS customer_name
        FROM reviews r
        INNER JOIN bookings b ON b.id = r.booking_id AND b.deleted_at IS NULL
        INNER JOIN drivers d ON d.id = r.driver_id AND d.deleted_at IS NULL
        LEFT JOIN users u ON u.id = r.customer_user_id AND u.deleted_at IS NULL
        LEFT JOIN user_profiles up ON up.user_id = u.id
        WHERE ${whereSql}
        ORDER BY r.created_at DESC, r.id DESC
        LIMIT ? OFFSET ?
      `,
      [...params, pagination.limit, pagination.offset],
    );
    return rows;
  }

  async findModerationActivityLogs(bookingId) {
    const [rows] = await this.pool.query(
      `
        SELECT
          id,
          activity_type,
          actor_user_id,
          actor_role,
          description,
          payload,
          created_at
        FROM booking_activity_logs
        WHERE booking_id = ?
          AND activity_type IN (
            'REVIEW_SUBMITTED',
            'REVIEW_HIDDEN',
            'REVIEW_RESTORED'
          )
        ORDER BY created_at ASC, id ASC
      `,
      [bookingId],
    );
    return rows;
  }
}

module.exports = ReviewRepository;

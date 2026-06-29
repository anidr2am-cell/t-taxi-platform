const database = require('../config/database');

class AdminDashboardRepository {
  constructor(pool = database.pool) {
    this.pool = pool;
  }

  async getBookingMetrics(range) {
    const [rows] = await this.pool.query(
      `
        SELECT
          COUNT(*) AS today,
          SUM(CASE WHEN b.status = 'PENDING' THEN 1 ELSE 0 END) AS pending,
          SUM(CASE WHEN b.status IN ('PENDING', 'CONFIRMED')
            AND NOT EXISTS (
              SELECT 1
              FROM booking_driver_assignments bda
              WHERE bda.booking_id = b.id
                AND bda.is_active = 1
                AND bda.deleted_at IS NULL
            )
            THEN 1 ELSE 0 END) AS unassigned,
          SUM(CASE WHEN b.status = 'DRIVER_ASSIGNED' THEN 1 ELSE 0 END) AS assigned,
          SUM(CASE WHEN b.status = 'PICKED_UP' THEN 1 ELSE 0 END) AS on_route,
          SUM(CASE WHEN b.status = 'DRIVER_ARRIVED' THEN 1 ELSE 0 END) AS arrived,
          SUM(CASE WHEN b.status = 'COMPLETED' THEN 1 ELSE 0 END) AS completed,
          SUM(CASE WHEN b.status = 'CANCELLED' THEN 1 ELSE 0 END) AS cancelled,
          SUM(CASE WHEN b.status = 'NO_SHOW' THEN 1 ELSE 0 END) AS no_show
        FROM bookings b
        WHERE b.deleted_at IS NULL
          AND b.scheduled_pickup_at >= ?
          AND b.scheduled_pickup_at < ?
      `,
      [range.start, range.end],
    );
    return rows[0] || {};
  }

  async getDriverMetrics() {
    const [rows] = await this.pool.query(
      `
        SELECT
          SUM(CASE WHEN d.is_online = 1 AND d.is_active = 1 AND d.status <> 'SUSPENDED'
            THEN 1 ELSE 0 END) AS online,
          COUNT(DISTINCT CASE WHEN b.id IS NOT NULL THEN d.id ELSE NULL END) AS active_jobs
        FROM drivers d
        LEFT JOIN booking_driver_assignments bda ON bda.driver_id = d.id
          AND bda.is_active = 1
          AND bda.deleted_at IS NULL
          AND bda.status IN ('ASSIGNED', 'ACCEPTED')
        LEFT JOIN bookings b ON b.id = bda.booking_id
          AND b.deleted_at IS NULL
          AND b.status NOT IN ('COMPLETED', 'CANCELLED', 'NO_SHOW')
        WHERE d.deleted_at IS NULL
      `,
    );
    return rows[0] || {};
  }

  async getSettlementMetrics(now) {
    const [rows] = await this.pool.query(
      `
        SELECT
          SUM(CASE WHEN b.commission_status IN ('DUE', 'OVERDUE')
            THEN 1 ELSE 0 END) AS pending,
          SUM(CASE WHEN b.commission_status = 'OVERDUE'
            OR (
              b.commission_status = 'DUE'
              AND b.commission_due_at IS NOT NULL
              AND b.commission_due_at < ?
              AND b.commission_receipt_file_id IS NULL
            )
            THEN 1 ELSE 0 END) AS overdue
        FROM bookings b
        WHERE b.deleted_at IS NULL
          AND b.status = 'COMPLETED'
          AND b.commission_status NOT IN ('NOT_DUE_YET', 'PAID', 'WAIVED')
      `,
      [now],
    );
    return rows[0] || {};
  }

  async getRevenueByCurrency(range) {
    const [rows] = await this.pool.query(
      `
        SELECT
          currency,
          SUM(CASE WHEN scheduled_pickup_at >= ?
            AND scheduled_pickup_at < ?
            AND status NOT IN ('CANCELLED', 'NO_SHOW')
            THEN total_amount ELSE 0 END) AS today_booked,
          SUM(CASE WHEN completed_at >= ?
            AND completed_at < ?
            AND status = 'COMPLETED'
            THEN total_amount ELSE 0 END) AS today_completed
        FROM bookings
        WHERE deleted_at IS NULL
          AND (
            (scheduled_pickup_at >= ? AND scheduled_pickup_at < ?)
            OR (completed_at >= ? AND completed_at < ?)
          )
        GROUP BY currency
        ORDER BY currency ASC
      `,
      [
        range.start,
        range.end,
        range.start,
        range.end,
        range.start,
        range.end,
        range.start,
        range.end,
      ],
    );
    return rows;
  }
}

module.exports = AdminDashboardRepository;

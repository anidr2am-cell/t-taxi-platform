const database = require('../config/database');

class BookingNoShowPenaltyRepository {
  constructor(pool = database.pool) {
    this.pool = pool;
  }

  async findByBookingId(bookingId, conn = null) {
    const executor = conn ?? this.pool;
    const [rows] = await executor.query(
      `
        SELECT
          id,
          booking_id,
          penalty_amount,
          currency,
          reason,
          created_by_admin_id,
          created_at,
          updated_at
        FROM booking_no_show_penalties
        WHERE booking_id = ?
        LIMIT 1
      `,
      [bookingId],
    );
    return rows[0] ?? null;
  }

  async insert(conn, row) {
    const [result] = await conn.query(
      `
        INSERT INTO booking_no_show_penalties (
          booking_id,
          penalty_amount,
          currency,
          reason,
          created_by_admin_id
        ) VALUES (?, ?, ?, ?, ?)
      `,
      [
        row.bookingId,
        row.penaltyAmount,
        row.currency ?? 'THB',
        row.reason,
        row.createdByAdminId,
      ],
    );

    const [rows] = await conn.query(
      `
        SELECT
          id,
          booking_id,
          penalty_amount,
          currency,
          reason,
          created_by_admin_id,
          created_at,
          updated_at
        FROM booking_no_show_penalties
        WHERE id = ?
        LIMIT 1
      `,
      [result.insertId],
    );
    return rows[0];
  }
}

module.exports = BookingNoShowPenaltyRepository;

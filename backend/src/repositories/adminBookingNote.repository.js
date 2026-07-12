const database = require('../config/database');

class AdminBookingNoteRepository {
  constructor(pool = database.pool) {
    this.pool = pool;
  }

  async findBookingByNumber(bookingNumber) {
    const [rows] = await this.pool.query(
      `SELECT id, booking_number, status, commission_status
       FROM bookings
       WHERE booking_number = ? AND deleted_at IS NULL
       LIMIT 1`,
      [bookingNumber],
    );
    return rows[0] ?? null;
  }

  async listByBookingId(bookingId, { limit, offset }) {
    const [rows] = await this.pool.query(
      `SELECT n.id, n.note_text, n.admin_user_id, n.created_at,
              COALESCE(up.display_name, u.email) AS author_name
       FROM admin_booking_notes n
       INNER JOIN users u ON u.id = n.admin_user_id AND u.deleted_at IS NULL
       LEFT JOIN user_profiles up ON up.user_id = u.id AND up.deleted_at IS NULL
       WHERE n.booking_id = ?
       ORDER BY n.created_at ASC, n.id ASC
       LIMIT ? OFFSET ?`,
      [bookingId, limit, offset],
    );
    return rows;
  }

  async countByBookingId(bookingId) {
    const [rows] = await this.pool.query(
      'SELECT COUNT(*) AS total FROM admin_booking_notes WHERE booking_id = ?',
      [bookingId],
    );
    return Number(rows[0]?.total ?? 0);
  }

  async insert(conn, { bookingId, adminUserId, text }) {
    const [result] = await conn.query(
      `INSERT INTO admin_booking_notes (booking_id, admin_user_id, note_text)
       VALUES (?, ?, ?)`,
      [bookingId, adminUserId, text],
    );
    return result.insertId;
  }

  async findById(noteId) {
    const [rows] = await this.pool.query(
      `SELECT n.id, n.note_text, n.admin_user_id, n.created_at,
              COALESCE(up.display_name, u.email) AS author_name
       FROM admin_booking_notes n
       INNER JOIN users u ON u.id = n.admin_user_id AND u.deleted_at IS NULL
       LEFT JOIN user_profiles up ON up.user_id = u.id AND up.deleted_at IS NULL
       WHERE n.id = ? LIMIT 1`,
      [noteId],
    );
    return rows[0] ?? null;
  }
}

module.exports = AdminBookingNoteRepository;

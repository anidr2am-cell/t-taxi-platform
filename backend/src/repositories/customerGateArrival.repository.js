class CustomerGateArrivalRepository {
  async hasNameSign(conn, bookingId) {
    const [rows] = await conn.query("SELECT id FROM booking_charge_items WHERE booking_id=? AND charge_type='NAME_SIGN' AND deleted_at IS NULL LIMIT 1", [bookingId]);
    return rows.length > 0;
  }
  async findActiveAssignment(conn, bookingId) {
    const [rows] = await conn.query(`SELECT a.id, a.driver_id, d.user_id, d.status
      FROM booking_driver_assignments a JOIN drivers d ON d.id=a.driver_id
      WHERE a.booking_id=? AND a.is_active=1 AND a.deleted_at IS NULL AND d.deleted_at IS NULL
      ORDER BY a.id DESC LIMIT 1 FOR UPDATE`, [bookingId]);
    return rows[0] ?? null;
  }
}
module.exports = CustomerGateArrivalRepository;

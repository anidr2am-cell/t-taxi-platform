const {extractAirlineCode}=require('../utils/flightNumber.util');
class CustomerBookingEditRepository {
  async find(conn, number) {
    const [rows] = await conn.query(`SELECT b.*,st.code service_type_code,t.flight_number
      FROM bookings b JOIN service_types st ON st.id=b.service_type_id
      LEFT JOIN booking_transfer_details t ON t.booking_id=b.id AND t.deleted_at IS NULL
      WHERE b.booking_number=? AND b.deleted_at IS NULL AND b.is_archived=0 LIMIT 1 FOR UPDATE`,[number]);
    return rows[0] ?? null;
  }
  async save(conn, row, next, flightChanged, resetContact) {
    await conn.query(`UPDATE bookings SET customer_phone=?,customer_email=?,special_requests=?,metadata=?,
      contact_status=IF(?, 'PENDING',contact_status),contact_verified_at=IF(?,NULL,contact_verified_at),
      contact_channel=IF(?, ?,contact_channel),updated_at=CURRENT_TIMESTAMP WHERE id=?`,
      [next.phone,next.email,next.specialRequests,JSON.stringify(next.metadata),resetContact,resetContact,resetContact,next.contactChannel,row.id]);
    if(flightChanged) await conn.query(`INSERT INTO booking_transfer_details(booking_id,flight_number,airline_code) VALUES(?,?,?)
      ON DUPLICATE KEY UPDATE deleted_at=NULL,flight_number=VALUES(flight_number),airline_code=VALUES(airline_code),departure_airport_iata=NULL,arrival_airport_iata=NULL,flight_scheduled_arrival_at=NULL,
      flight_estimated_arrival_at=NULL,flight_actual_arrival_at=NULL,delay_status=NULL,delay_minutes=NULL,last_synced_at=NULL,flight_status=NULL,flight_raw_data=NULL,sync_status='NEVER',sync_error=NULL`,[row.id,next.flightNumber,extractAirlineCode(next.flightNumber)]);
  }
  async assignment(conn,id) {
    const [rows]=await conn.query(`SELECT a.id,a.driver_id,d.user_id,d.status FROM booking_driver_assignments a
      JOIN drivers d ON d.id=a.driver_id AND d.deleted_at IS NULL
      WHERE a.booking_id=? AND a.is_active=1 AND a.deleted_at IS NULL ORDER BY a.id DESC LIMIT 1 FOR UPDATE`,[id]);
    return rows[0] ?? null;
  }
}
module.exports=CustomerBookingEditRepository;

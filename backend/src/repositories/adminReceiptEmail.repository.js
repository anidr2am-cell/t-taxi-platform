const database = require('../config/database');
class AdminReceiptEmailRepository {
  constructor(pool=database.pool) { this.pool=pool; }
  async booking(conn,number,lock=false) {
    const [rows]=await (conn||this.pool).query(`SELECT b.id,b.booking_number,b.status,b.customer_email,
      b.total_amount,b.currency,b.payment_status,b.payment_method,b.metadata,
      b.scheduled_pickup_at,b.origin_address,b.destination_address,vt.code AS vehicle_type_code
      FROM bookings b LEFT JOIN vehicle_types vt ON vt.id=b.vehicle_type_id
      WHERE b.booking_number=? AND b.deleted_at IS NULL LIMIT 1 ${lock?'FOR UPDATE':''}`,[number]);
    return rows[0]||null;
  }
  async history(conn,id) {
    const [rows]=await (conn||this.pool).query(`SELECT d.id,d.notification_id,n.type,d.delivery_status,d.attempt_count,d.last_error,
      (SELECT COUNT(*) FROM notification_email_attempts a WHERE a.delivery_id=d.id) smtp_attempts,
      (SELECT a.outcome FROM notification_email_attempts a WHERE a.delivery_id=d.id ORDER BY a.id DESC LIMIT 1) outcome,
      (SELECT COUNT(*) FROM notification_email_reviews r WHERE r.delivery_id=d.id AND r.action='ACCEPTED_CONFIRMED') accepted_confirmed
      FROM notification_deliveries d JOIN notifications n ON n.id=d.notification_id
      LEFT JOIN users u ON u.id=n.user_id
      WHERE n.booking_id=? AND d.channel='EMAIL'
        AND COALESCE(n.audience_role,IF(n.recipient_type='GUEST_BOOKING','CUSTOMER',u.role))='CUSTOMER'
      ORDER BY d.id DESC`,[id]);
    return rows;
  }
  async confirmPayment(conn,row,record,actorId) {
    await conn.query(`UPDATE bookings SET payment_status='PAID',
      metadata=JSON_SET(COALESCE(metadata,JSON_OBJECT()),'$.customerPaymentConfirmation',JSON_EXTRACT(?,'$')),
      updated_by=?,updated_at=CURRENT_TIMESTAMP WHERE id=?`,[JSON.stringify(record),actorId,row.id]);
  }
  async approve(conn,row,email,record) {
    await conn.query(`UPDATE bookings SET customer_email=?,metadata=JSON_SET(COALESCE(metadata,JSON_OBJECT()),
      '$.adminReceiptEmail',JSON_EXTRACT(?,'$')) WHERE id=?`,[email,JSON.stringify(record),row.id]);
    // Only EMAIL rows with no SMTP attempt can be superseded. Other channels stay untouched.
    await conn.query(`UPDATE notification_deliveries d JOIN notifications n ON n.id=d.notification_id
      LEFT JOIN users u ON u.id=n.user_id
      SET d.delivery_status='SKIPPED',d.last_error='EMAIL_POLICY_SUPERSEDED_BY_ADMIN_RECEIPT'
      WHERE n.booking_id=? AND d.channel='EMAIL' AND d.delivery_status<>'DELIVERED' AND d.id<>?
        AND (d.attempt_count=0 OR d.last_error IN ('PERMANENT_INVALID_RECIPIENT','CONFIG_MISSING') OR d.last_error LIKE 'EMAIL_POLICY_%')
        AND COALESCE(n.audience_role,IF(n.recipient_type='GUEST_BOOKING','CUSTOMER',u.role))='CUSTOMER'
        AND NOT EXISTS(SELECT 1 FROM notification_email_attempts a WHERE a.delivery_id=d.id)`,[row.id,record.deliveryId]);
  }
}
module.exports=AdminReceiptEmailRepository;

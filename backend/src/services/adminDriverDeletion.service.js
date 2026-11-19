const AppError = require('../utils/AppError');
const { getRealtimeIo, driverUserRoom } = require('../socket/realtime');

async function deleteDriver(pool, driverId, reason, actor) {
  const conn = await pool.getConnection();
  let userId;
  try {
    await conn.beginTransaction();
    const [[driver]] = await conn.query(
      'SELECT id, user_id, deleted_at FROM drivers WHERE id=? FOR UPDATE', [driverId],
    );
    if (!driver || driver.deleted_at) {
      throw new AppError('Driver not found', { statusCode: 404, errorCode: 'DRIVER_NOT_FOUND' });
    }
    userId = driver.user_id;
    const [[user]] = await conn.query('SELECT id, role FROM users WHERE id=? FOR UPDATE', [userId]);
    if (!user || user.role !== 'DRIVER') {
      throw new AppError('Driver account cannot be deleted', { statusCode: 409, errorCode: 'DRIVER_DELETE_BLOCKED' });
    }
    // Lock the same driver row used by assignment and suspension, then check
    // current obligations inside the transaction, including archived bookings.
    const [blocking] = await conn.query(`
      SELECT b.booking_number FROM bookings b
      WHERE b.deleted_at IS NULL
        AND (b.driver_id=? OR EXISTS (
          SELECT 1 FROM booking_driver_assignments a
          WHERE a.booking_id=b.id AND a.driver_id=? AND a.deleted_at IS NULL
            AND a.is_active=1))
        AND (b.status IN ('DRIVER_ASSIGNED','ON_ROUTE','DRIVER_ARRIVED','PICKED_UP')
          OR b.commission_status IN ('DUE','OVERDUE'))
      FOR UPDATE`, [driverId, driverId]);
    if (blocking.length) {
      throw new AppError('Finish assignments and settlements before deleting this driver', {
        statusCode: 409, errorCode: 'DRIVER_DELETE_BLOCKED',
        details: { bookingNumbers: blocking.map(row => row.booking_number) },
        errors: blocking.map(row => ({ field: 'bookingNumber', message: row.booking_number })),
      });
    }
    await conn.query(`UPDATE drivers SET deleted_at=CURRENT_TIMESTAMP,
      is_online=0, updated_at=CURRENT_TIMESTAMP WHERE id=?`, [driverId]);
    await conn.query(`UPDATE users SET is_active=0,
      auth_token_version=auth_token_version+1, updated_at=CURRENT_TIMESTAMP WHERE id=?`, [userId]);
    await conn.query(`INSERT INTO audit_logs (user_id,action,entity_type,entity_id,payload)
      VALUES (?,'DRIVER_DELETED','driver',?,?)`,
    [actor.id, driverId, JSON.stringify({ reason, driverId, userId })]);
    await conn.commit();
  } catch (error) {
    await conn.rollback();
    throw error;
  } finally {
    conn.release();
  }
  getRealtimeIo()?.in(driverUserRoom(userId)).disconnectSockets(true);
  return { driverId, deleted: true };
}

module.exports = { deleteDriver };

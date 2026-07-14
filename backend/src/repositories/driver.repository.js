const database = require('../config/database');
const SCORING = require('../constants/driverAssignmentScoring');

class DriverRepository {
  constructor(pool = database.pool) {
    this.pool = pool;
  }

  async listForAdminAssignment() {
    const [rows] = await this.pool.query(
      `
        SELECT
          d.id,
          d.name,
          d.phone,
          d.status,
          d.is_online,
          d.is_active,
          d.primary_vehicle_type_id,
          vt.code AS primary_vehicle_type_code,
          vt.name AS primary_vehicle_type_name,
          dv.id AS primary_vehicle_id,
          dv.plate_number AS primary_vehicle_plate,
          dv.model_name AS primary_vehicle_model,
          (
            SELECT COUNT(*)
            FROM booking_driver_assignments bda
            INNER JOIN bookings b ON b.id = bda.booking_id AND b.deleted_at IS NULL
            WHERE bda.driver_id = d.id
              AND bda.is_active = 1
              AND bda.deleted_at IS NULL
              AND bda.status IN ('ASSIGNED', 'ACCEPTED')
              AND b.status IN ('DRIVER_ASSIGNED', 'ON_ROUTE', 'DRIVER_ARRIVED', 'PICKED_UP', 'SETTLEMENT_PENDING')
          ) AS active_assignment_count,
          (
            SELECT ROUND(AVG(r.rating), 1)
            FROM reviews r
            WHERE r.driver_id = d.id
              AND r.moderation_status = 'VISIBLE'
          ) AS average_rating,
          (
            SELECT COUNT(*)
            FROM reviews r
            WHERE r.driver_id = d.id
              AND r.moderation_status = 'VISIBLE'
          ) AS review_count
        FROM drivers d
        LEFT JOIN vehicle_types vt ON vt.id = d.primary_vehicle_type_id AND vt.deleted_at IS NULL
        LEFT JOIN driver_vehicles dv ON dv.driver_id = d.id
          AND dv.is_primary = 1
          AND dv.is_active = 1
          AND dv.deleted_at IS NULL
        WHERE d.deleted_at IS NULL
        ORDER BY d.name ASC
      `,
    );
    return rows;
  }

  async listForCandidateEvaluation(scheduledPickupAt) {
    const [rows] = await this.pool.query(
      `
        SELECT
          d.id,
          d.name,
          d.phone,
          d.status,
          d.is_online,
          d.is_active,
          d.primary_vehicle_type_id,
          d.current_lat,
          d.current_lng,
          d.location_updated_at,
          d.location_recorded_at,
          u.is_active AS user_is_active,
          vt.code AS primary_vehicle_type_code,
          dv.id AS primary_vehicle_id,
          dv.vehicle_type_id,
          (
            SELECT COUNT(*)
            FROM booking_driver_assignments bda
            INNER JOIN bookings b ON b.id = bda.booking_id AND b.deleted_at IS NULL
            WHERE bda.driver_id = d.id
              AND bda.is_active = 1
              AND bda.deleted_at IS NULL
              AND bda.status IN ('ASSIGNED', 'ACCEPTED')
              AND b.status IN ('DRIVER_ASSIGNED', 'ON_ROUTE', 'DRIVER_ARRIVED', 'PICKED_UP', 'SETTLEMENT_PENDING')
          ) AS active_assignment_count,
          (
            SELECT ROUND(AVG(r.rating), 1)
            FROM reviews r
            WHERE r.driver_id = d.id
              AND r.moderation_status = 'VISIBLE'
          ) AS average_rating,
          (
            SELECT COUNT(*)
            FROM booking_driver_assignments bda
            INNER JOIN bookings b ON b.id = bda.booking_id AND b.deleted_at IS NULL
            WHERE bda.driver_id = d.id
              AND bda.deleted_at IS NULL
              AND DATE(bda.assigned_at) = CURDATE()
          ) AS assignments_today_count,
          (
            SELECT MAX(bda.assigned_at)
            FROM booking_driver_assignments bda
            WHERE bda.driver_id = d.id
              AND bda.deleted_at IS NULL
          ) AS last_assigned_at,
          (
            SELECT COUNT(*)
            FROM booking_driver_assignments bda
            INNER JOIN bookings b ON b.id = bda.booking_id AND b.deleted_at IS NULL
            WHERE bda.driver_id = d.id
              AND bda.is_active = 1
              AND bda.deleted_at IS NULL
              AND bda.status IN ('ASSIGNED', 'ACCEPTED')
              AND b.status IN ('DRIVER_ASSIGNED', 'ON_ROUTE', 'DRIVER_ARRIVED', 'PICKED_UP', 'SETTLEMENT_PENDING')
              AND b.scheduled_pickup_at IS NOT NULL
              AND ? IS NOT NULL
              AND ABS(TIMESTAMPDIFF(MINUTE, b.scheduled_pickup_at, ?)) <= ?
          ) AS schedule_conflict_count
        FROM drivers d
        INNER JOIN users u ON u.id = d.user_id AND u.deleted_at IS NULL
        LEFT JOIN vehicle_types vt ON vt.id = d.primary_vehicle_type_id AND vt.deleted_at IS NULL
        LEFT JOIN driver_vehicles dv ON dv.driver_id = d.id
          AND dv.is_primary = 1
          AND dv.is_active = 1
          AND dv.deleted_at IS NULL
        WHERE d.deleted_at IS NULL
        ORDER BY d.name ASC
      `,
      [
        scheduledPickupAt,
        scheduledPickupAt,
        Math.floor(SCORING.SCHEDULE_CONFLICT_WINDOW_MS / 60000),
      ],
    );
    return rows;
  }

  async findByIdForUpdate(conn, driverId) {
    const [rows] = await conn.query(
      `
        SELECT
          d.id,
          d.user_id,
          d.name,
          d.phone,
          d.status,
          d.is_online,
          d.is_active
        FROM drivers d
        WHERE d.id = ? AND d.deleted_at IS NULL
        LIMIT 1
        FOR UPDATE
      `,
      [driverId],
    );
    return rows[0] || null;
  }

  async findByUserIdForUpdate(conn, userId) {
    const [rows] = await conn.query(
      `
        SELECT
          d.id,
          d.user_id,
          d.name,
          d.phone,
          d.status,
          d.is_online,
          d.is_active,
          d.last_seen_at,
          u.is_active AS user_is_active
        FROM drivers d
        INNER JOIN users u ON u.id = d.user_id AND u.deleted_at IS NULL
        WHERE d.user_id = ? AND d.deleted_at IS NULL
        LIMIT 1
        FOR UPDATE
      `,
      [userId],
    );
    return rows[0] || null;
  }

  async updateOnlineState(conn, driverId, { isOnline, status }) {
    await conn.query(
      `
        UPDATE drivers
        SET is_online = ?,
            status = ?,
            last_seen_at = CURRENT_TIMESTAMP,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = ? AND deleted_at IS NULL
      `,
      [isOnline ? 1 : 0, status, driverId],
    );
  }

  async hasActiveJob(conn, driverId) {
    const [rows] = await conn.query(
      `
        SELECT 1
        FROM booking_driver_assignments bda
        INNER JOIN bookings b ON b.id = bda.booking_id AND b.deleted_at IS NULL
        WHERE bda.driver_id = ?
          AND bda.is_active = 1
          AND bda.deleted_at IS NULL
          AND bda.status IN ('ASSIGNED', 'ACCEPTED')
          AND b.status IN ('DRIVER_ASSIGNED', 'ON_ROUTE', 'DRIVER_ARRIVED', 'PICKED_UP', 'SETTLEMENT_PENDING')
        LIMIT 1
      `,
      [driverId],
    );
    return rows.length > 0;
  }

  async findPrimaryVehicle(conn, driverId) {
    const [rows] = await conn.query(
      `
        SELECT id, vehicle_type_id, plate_number, model_name
        FROM driver_vehicles
        WHERE driver_id = ?
          AND is_primary = 1
          AND is_active = 1
          AND deleted_at IS NULL
        LIMIT 1
      `,
      [driverId],
    );
    return rows[0] || null;
  }

  async findMatchingVehicle(conn, driverId, vehicleTypeId) {
    const [rows] = await conn.query(
      `
        SELECT id, vehicle_type_id, plate_number, model_name
        FROM driver_vehicles
        WHERE driver_id = ?
          AND vehicle_type_id = ?
          AND is_active = 1
          AND deleted_at IS NULL
        ORDER BY is_primary DESC, id ASC
        LIMIT 1
      `,
      [driverId, vehicleTypeId],
    );
    return rows[0] || null;
  }

  async listEligibleForOpenBooking(conn, vehicleTypeId, options = {}) {
    const executor = conn ?? this.pool;
    const excludeReleasedBookingId = options.excludeReleasedBookingId ?? null;
    const [rows] = await executor.query(
      `
        SELECT
          d.id,
          d.user_id,
          d.name,
          d.status,
          d.is_online,
          d.is_active,
          u.is_active AS user_is_active,
          dv.id AS driver_vehicle_id,
          dv.vehicle_type_id
        FROM drivers d
        INNER JOIN users u ON u.id = d.user_id
          AND u.role = 'DRIVER'
          AND u.is_active = 1
          AND u.deleted_at IS NULL
        INNER JOIN driver_vehicles dv ON dv.id = (
          SELECT dv2.id
          FROM driver_vehicles dv2
          WHERE dv2.driver_id = d.id
            AND dv2.vehicle_type_id = ?
            AND dv2.is_active = 1
            AND dv2.deleted_at IS NULL
          ORDER BY dv2.is_primary DESC, dv2.id ASC
          LIMIT 1
        )
        WHERE d.deleted_at IS NULL
          AND d.is_active = 1
          AND d.is_online = 1
          AND d.status = 'AVAILABLE'
          AND NOT EXISTS (
            SELECT 1
            FROM booking_driver_assignments bda
            INNER JOIN bookings b ON b.id = bda.booking_id AND b.deleted_at IS NULL
            WHERE bda.driver_id = d.id
              AND bda.is_active = 1
              AND bda.deleted_at IS NULL
              AND bda.status IN ('ASSIGNED', 'ACCEPTED')
              AND b.status IN ('DRIVER_ASSIGNED', 'ON_ROUTE', 'DRIVER_ARRIVED', 'PICKED_UP', 'SETTLEMENT_PENDING')
          )
          AND (
            ? IS NULL
            OR NOT EXISTS (
              SELECT 1
              FROM booking_driver_assignments released_bda
              WHERE released_bda.booking_id = ?
                AND released_bda.driver_id = d.id
                AND released_bda.is_active = 0
                AND released_bda.deleted_at IS NULL
                AND released_bda.assignment_reason = 'DRIVER_RELEASED_ASSIGNMENT'
            )
          )
        ORDER BY d.last_seen_at DESC, d.id ASC
      `,
      [vehicleTypeId, excludeReleasedBookingId, excludeReleasedBookingId],
    );
    return rows;
  }

  async findById(driverId) {
    const [rows] = await this.pool.query(
      `
        SELECT id, user_id, name, phone, status, is_online, is_active
        FROM drivers
        WHERE id = ? AND deleted_at IS NULL
        LIMIT 1
      `,
      [driverId],
    );
    return rows[0] || null;
  }

  async findByUserId(userId) {
    const [rows] = await this.pool.query(
      `
        SELECT
          d.id,
          d.user_id,
          d.name,
          d.phone,
          d.status,
          d.is_online,
          d.is_active,
          d.last_seen_at,
          u.is_active AS user_is_active,
          (
            SELECT COUNT(*)
            FROM booking_driver_assignments bda
            INNER JOIN bookings b ON b.id = bda.booking_id AND b.deleted_at IS NULL
            WHERE bda.driver_id = d.id
              AND bda.is_active = 1
              AND bda.deleted_at IS NULL
              AND bda.status IN ('ASSIGNED', 'ACCEPTED')
              AND b.status IN ('DRIVER_ASSIGNED', 'ON_ROUTE', 'DRIVER_ARRIVED', 'PICKED_UP', 'SETTLEMENT_PENDING')
          ) AS active_job_count,
          (
            SELECT COUNT(*)
            FROM driver_vehicles dv
            WHERE dv.driver_id = d.id
              AND dv.is_active = 1
              AND dv.deleted_at IS NULL
          ) AS active_vehicle_count
        FROM drivers d
        INNER JOIN users u ON u.id = d.user_id AND u.deleted_at IS NULL
        WHERE d.user_id = ? AND d.deleted_at IS NULL
        LIMIT 1
      `,
      [userId],
    );
    return rows[0] || null;
  }
}

module.exports = DriverRepository;

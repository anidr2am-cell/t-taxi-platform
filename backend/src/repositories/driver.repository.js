const database = require('../config/database');
const SCORING = require('../constants/driverAssignmentScoring');

class DriverRepository {
  constructor(pool = database.pool) {
    this.pool = pool;
  }

  async listForAdminAssignment({ archived = false } = {}) {
    const [rows] = await this.pool.query(
      `
        SELECT
          d.id,
          d.name,
          d.phone,
          d.status,
          d.is_online,
          d.is_active,
          d.is_archived,
          d.archived_at,
          d.archive_reason,
          d.primary_vehicle_type_id,
          vt.code AS primary_vehicle_type_code,
          vt.name AS primary_vehicle_type_name,
          dv.id AS primary_vehicle_id,
          dv.plate_number AS primary_vehicle_plate,
          dv.model_name AS primary_vehicle_model,
          (
            SELECT COUNT(*)
            FROM booking_driver_assignments bda
            INNER JOIN bookings b ON b.id = bda.booking_id AND b.deleted_at IS NULL AND b.is_archived = 0
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
          AND d.is_archived = ?
        ORDER BY d.name ASC
      `,
      [archived ? 1 : 0],
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
            INNER JOIN bookings b ON b.id = bda.booking_id AND b.deleted_at IS NULL AND b.is_archived = 0
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
            INNER JOIN bookings b ON b.id = bda.booking_id AND b.deleted_at IS NULL AND b.is_archived = 0
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
            INNER JOIN bookings b ON b.id = bda.booking_id AND b.deleted_at IS NULL AND b.is_archived = 0
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
          AND d.is_archived = 0
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
          d.is_active,
          d.is_archived
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
        WHERE d.user_id = ? AND d.deleted_at IS NULL AND d.is_archived = 0
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
        INNER JOIN bookings b ON b.id = bda.booking_id AND b.deleted_at IS NULL AND b.is_archived = 0
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
          AND d.is_archived = 0
          AND d.is_active = 1
          AND d.is_online = 1
          AND d.status = 'AVAILABLE'
          AND NOT EXISTS (
            SELECT 1
            FROM booking_driver_assignments bda
            INNER JOIN bookings b ON b.id = bda.booking_id AND b.deleted_at IS NULL AND b.is_archived = 0
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
            INNER JOIN bookings b ON b.id = bda.booking_id AND b.deleted_at IS NULL AND b.is_archived = 0
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
        WHERE d.user_id = ? AND d.deleted_at IS NULL AND d.is_archived = 0
        LIMIT 1
      `,
      [userId],
    );
    return rows[0] || null;
  }

  async findArchiveCandidatesForUpdate(conn, driverIds) {
    if (!driverIds.length) return [];
    const placeholders = driverIds.map(() => '?').join(', ');
    const [rows] = await conn.query(
      `
        SELECT
          d.id,
          d.user_id,
          d.name,
          d.status,
          d.is_online,
          d.is_active,
          d.is_archived,
          d.archive_reason,
          (
            SELECT COUNT(*)
            FROM booking_driver_assignments bda
            WHERE bda.driver_id = d.id
              AND bda.deleted_at IS NULL
          ) AS assignment_count,
          (
            SELECT COUNT(*)
            FROM booking_driver_assignments bda
            INNER JOIN bookings b ON b.id = bda.booking_id
              AND b.deleted_at IS NULL
              AND b.is_archived = 0
            WHERE bda.driver_id = d.id
              AND bda.is_active = 1
              AND bda.deleted_at IS NULL
              AND bda.status IN ('ASSIGNED', 'ACCEPTED')
              AND b.status IN ('DRIVER_ASSIGNED', 'ON_ROUTE', 'DRIVER_ARRIVED', 'PICKED_UP', 'SETTLEMENT_PENDING')
          ) AS active_assignment_count,
          (
            SELECT COUNT(*)
            FROM bookings b
            WHERE b.driver_id = d.id
              AND b.deleted_at IS NULL
              AND b.status IN ('COMPLETED', 'SETTLEMENT_PENDING')
          ) AS completed_trip_count,
          (
            SELECT COUNT(*)
            FROM bookings b
            WHERE b.driver_id = d.id
              AND b.deleted_at IS NULL
              AND b.commission_status IS NOT NULL
              AND b.commission_status <> 'NOT_DUE_YET'
          ) AS settlement_count,
          (
            SELECT COUNT(*)
            FROM chat_messages cm
            INNER JOIN chat_participants cp ON cp.id = cm.sender_participant_id
            WHERE cp.user_id = d.user_id
              AND cm.deleted_at IS NULL
          ) AS message_count,
          (
            SELECT COUNT(*)
            FROM reviews r
            WHERE r.driver_id = d.id
          ) AS review_count,
          (
            SELECT COUNT(*)
            FROM driver_vehicles dv
            WHERE dv.driver_id = d.id
              AND dv.deleted_at IS NULL
          ) AS vehicle_count
        FROM drivers d
        WHERE d.id IN (${placeholders})
          AND d.deleted_at IS NULL
        FOR UPDATE
      `,
      driverIds,
    );
    return rows;
  }

  async archiveDrivers(conn, driverIds, { actorUserId, reason }) {
    if (!driverIds.length) return 0;
    const placeholders = driverIds.map(() => '?').join(', ');
    const [result] = await conn.query(
      `
        UPDATE drivers
        SET
          is_archived = 1,
          archived_at = CURRENT_TIMESTAMP,
          archived_by = ?,
          archive_reason = ?,
          is_online = 0,
          status = 'OFFLINE',
          updated_at = CURRENT_TIMESTAMP
        WHERE id IN (${placeholders})
          AND deleted_at IS NULL
      `,
      [actorUserId, reason, ...driverIds],
    );
    return result.affectedRows;
  }

  async restoreDriver(conn, driverId, { actorUserId }) {
    const [result] = await conn.query(
      `
        UPDATE drivers
        SET
          is_archived = 0,
          archived_at = NULL,
          archived_by = NULL,
          archive_reason = NULL,
          updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
          AND deleted_at IS NULL
      `,
      [driverId],
    );
    return result.affectedRows;
  }

  async insertAuditLog(conn, { userId, action, driverId, payload }) {
    await conn.query(
      `
        INSERT INTO audit_logs (user_id, action, entity_type, entity_id, payload)
        VALUES (?, ?, 'driver', ?, ?)
      `,
      [userId, action, driverId, JSON.stringify(payload ?? {})],
    );
  }

  async findActiveAssignmentPickupsForConflict(conn, driverId, excludeBookingId = null) {
    const params = [driverId];
    let excludeSql = '';
    if (excludeBookingId != null) {
      excludeSql = 'AND b.id <> ?';
      params.push(excludeBookingId);
    }
    const [rows] = await conn.query(
      `
        SELECT
          b.id,
          b.booking_number,
          b.scheduled_pickup_at
        FROM booking_driver_assignments bda
        INNER JOIN bookings b ON b.id = bda.booking_id
          AND b.deleted_at IS NULL
          AND b.is_archived = 0
        WHERE bda.driver_id = ?
          AND bda.is_active = 1
          AND bda.deleted_at IS NULL
          AND bda.status IN ('ASSIGNED', 'ACCEPTED')
          AND b.status IN ('DRIVER_ASSIGNED', 'ON_ROUTE', 'DRIVER_ARRIVED', 'PICKED_UP', 'SETTLEMENT_PENDING')
          ${excludeSql}
      `,
      params,
    );
    return rows;
  }

  async findProfileByUserId(userId) {
    const [rows] = await this.pool.query(
      `
        SELECT
          d.id AS driver_id,
          d.user_id,
          d.name,
          d.phone,
          d.status,
          d.is_active,
          u.email,
          u.phone AS user_phone,
          up.display_name,
          up.avatar_url,
          dv.id AS vehicle_id,
          dv.plate_number,
          dv.model_name,
          dv.color,
          vt.id AS vehicle_type_id,
          vt.code AS vehicle_type_code,
          vt.name AS vehicle_type_name,
          da.id AS application_id,
          da.vehicle_year,
          (
            SELECT f.id
            FROM driver_application_files daf
            INNER JOIN files f ON f.id = daf.file_id AND f.deleted_at IS NULL
            WHERE daf.driver_application_id = da.id
              AND daf.category = 'DRIVER_VEHICLE_PHOTO'
            ORDER BY daf.sort_order ASC, f.id ASC
            LIMIT 1
          ) AS vehicle_photo_file_id
        FROM drivers d
        INNER JOIN users u ON u.id = d.user_id AND u.deleted_at IS NULL
        LEFT JOIN user_profiles up ON up.user_id = d.user_id AND up.deleted_at IS NULL
        LEFT JOIN driver_vehicles dv ON dv.driver_id = d.id
          AND dv.is_primary = 1
          AND dv.is_active = 1
          AND dv.deleted_at IS NULL
        LEFT JOIN vehicle_types vt ON vt.id = dv.vehicle_type_id AND vt.deleted_at IS NULL
        LEFT JOIN driver_applications da ON da.approved_driver_id = d.id
          AND da.status = 'APPROVED'
          AND da.deleted_at IS NULL
        WHERE d.user_id = ?
          AND d.deleted_at IS NULL
          AND d.is_archived = 0
        LIMIT 1
      `,
      [userId],
    );
    return rows[0] || null;
  }

  async findProfileByUserIdForUpdate(conn, userId) {
    const [rows] = await conn.query(
      `
        SELECT
          d.id,
          d.user_id,
          d.name,
          d.phone,
          d.primary_vehicle_type_id,
          u.email,
          u.phone AS user_phone,
          up.id AS profile_id,
          up.avatar_url,
          dv.id AS vehicle_id,
          dv.vehicle_type_id,
          dv.plate_number,
          dv.model_name,
          dv.color,
          da.id AS application_id,
          da.vehicle_year
        FROM drivers d
        INNER JOIN users u ON u.id = d.user_id AND u.deleted_at IS NULL
        LEFT JOIN user_profiles up ON up.user_id = d.user_id AND up.deleted_at IS NULL
        LEFT JOIN driver_vehicles dv ON dv.driver_id = d.id
          AND dv.is_primary = 1
          AND dv.is_active = 1
          AND dv.deleted_at IS NULL
        LEFT JOIN driver_applications da ON da.approved_driver_id = d.id
          AND da.status = 'APPROVED'
          AND da.deleted_at IS NULL
        WHERE d.user_id = ?
          AND d.deleted_at IS NULL
          AND d.is_archived = 0
        LIMIT 1
        FOR UPDATE
      `,
      [userId],
    );
    return rows[0] || null;
  }

  async updateSelfProfile(conn, { driverId, userId, name, phone, actorUserId }) {
    await conn.query(
      `
        UPDATE drivers
        SET name = ?, phone = ?, updated_by = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ? AND deleted_at IS NULL
      `,
      [name, phone, actorUserId, driverId],
    );
    await conn.query(
      `
        UPDATE users
        SET phone = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ? AND deleted_at IS NULL
      `,
      [phone, userId],
    );
    if (name) {
      const [existing] = await conn.query(
        `SELECT id FROM user_profiles WHERE user_id = ? AND deleted_at IS NULL LIMIT 1`,
        [userId],
      );
      if (existing[0]) {
        await conn.query(
          `
            UPDATE user_profiles
            SET display_name = ?, updated_at = CURRENT_TIMESTAMP
            WHERE user_id = ? AND deleted_at IS NULL
          `,
          [name, userId],
        );
      } else {
        await conn.query(
          `INSERT INTO user_profiles (user_id, display_name) VALUES (?, ?)`,
          [userId, name],
        );
      }
    }
  }

  async updatePrimaryVehicle(conn, { vehicleId, driverId, vehicleTypeId, plateNumber, modelName, color, actorUserId }) {
    await conn.query(
      `
        UPDATE driver_vehicles
        SET
          vehicle_type_id = ?,
          plate_number = ?,
          model_name = ?,
          color = ?,
          updated_by = ?,
          updated_at = CURRENT_TIMESTAMP
        WHERE id = ? AND driver_id = ? AND deleted_at IS NULL
      `,
      [vehicleTypeId, plateNumber, modelName, color, actorUserId, vehicleId, driverId],
    );
    await conn.query(
      `
        UPDATE drivers
        SET primary_vehicle_type_id = ?, updated_by = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ? AND deleted_at IS NULL
      `,
      [vehicleTypeId, actorUserId, driverId],
    );
  }

  async insertPrimaryVehicle(conn, { driverId, vehicleTypeId, plateNumber, modelName, color, actorUserId }) {
    const [result] = await conn.query(
      `
        INSERT INTO driver_vehicles (
          driver_id, vehicle_type_id, plate_number, model_name, color,
          is_primary, is_active, created_by, updated_by
        ) VALUES (?, ?, ?, ?, ?, 1, 1, ?, ?)
      `,
      [driverId, vehicleTypeId, plateNumber, modelName, color, actorUserId, actorUserId],
    );
    await conn.query(
      `
        UPDATE drivers
        SET primary_vehicle_type_id = ?, updated_by = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ? AND deleted_at IS NULL
      `,
      [vehicleTypeId, actorUserId, driverId],
    );
    return result.insertId;
  }

  async updateApplicationVehicleYear(conn, applicationId, vehicleYear) {
    await conn.query(
      `
        UPDATE driver_applications
        SET vehicle_year = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ? AND deleted_at IS NULL
      `,
      [vehicleYear, applicationId],
    );
  }

  async updateAvatarUrl(conn, userId, avatarUrl) {
    const [existing] = await conn.query(
      `SELECT id FROM user_profiles WHERE user_id = ? AND deleted_at IS NULL LIMIT 1`,
      [userId],
    );
    if (existing[0]) {
      await conn.query(
        `
          UPDATE user_profiles
          SET avatar_url = ?, updated_at = CURRENT_TIMESTAMP
          WHERE user_id = ? AND deleted_at IS NULL
        `,
        [avatarUrl, userId],
      );
    } else {
      await conn.query(
        `INSERT INTO user_profiles (user_id, avatar_url) VALUES (?, ?)`,
        [userId, avatarUrl],
      );
    }
  }

  async findAvatarFileByUserId(userId) {
    const [rows] = await this.pool.query(
      `
        SELECT f.id, f.file_path, f.mime_type, f.original_filename
        FROM files f
        WHERE f.entity_type = 'DRIVER_AVATAR'
          AND f.entity_id = ?
          AND f.deleted_at IS NULL
        ORDER BY f.id DESC
        LIMIT 1
      `,
      [userId],
    );
    return rows[0] || null;
  }

  async findVehiclePhotoFileByDriverId(driverId) {
    const [rows] = await this.pool.query(
      `
        SELECT f.id, f.file_path, f.mime_type, f.original_filename
        FROM driver_applications da
        INNER JOIN driver_application_files daf
          ON daf.driver_application_id = da.id
         AND daf.category = 'DRIVER_VEHICLE_PHOTO'
        INNER JOIN files f ON f.id = daf.file_id AND f.deleted_at IS NULL
        WHERE da.approved_driver_id = ?
          AND da.status = 'APPROVED'
          AND da.deleted_at IS NULL
        ORDER BY daf.sort_order ASC, f.id DESC
        LIMIT 1
      `,
      [driverId],
    );
    return rows[0] || null;
  }
}

module.exports = DriverRepository;

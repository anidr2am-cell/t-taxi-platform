const database = require('../config/database');

class DriverApplicationRepository {
  constructor(pool = database.pool) {
    this.pool = pool;
  }

  async create(conn, data) {
    const [result] = await conn.query(
      `
        INSERT INTO driver_applications (
          application_number, status, email, password_hash, full_name, phone,
          phone_country_code, country_code, locale, driving_license_number,
          driving_license_country, driving_license_expiry_date,
          years_of_driving_experience, vehicle_ownership_type, vehicle_type_code,
          vehicle_make, vehicle_model, vehicle_year, vehicle_color,
          vehicle_plate_number, service_areas, languages, notes,
          bank_name, bank_account_number, bank_account_holder, line_id,
          primary_service_area,
          personal_data_consent_at, driver_terms_consent_at,
          status_lookup_token_hash, submitted_at, resubmitted_from_application_id
        ) VALUES (
          ?, 'PENDING', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
          ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP,
          ?, CURRENT_TIMESTAMP, ?
        )
      `,
      [
        data.applicationNumber,
        data.email,
        data.passwordHash,
        data.fullName,
        data.phone,
        data.phoneCountryCode,
        data.countryCode,
        data.locale,
        data.drivingLicenseNumber,
        data.drivingLicenseCountry,
        data.drivingLicenseExpiryDate,
        data.yearsOfDrivingExperience,
        data.vehicleOwnershipType,
        data.vehicleTypeCode,
        data.vehicleMake,
        data.vehicleModel,
        data.vehicleYear,
        data.vehicleColor,
        data.vehiclePlateNumber,
        JSON.stringify(data.serviceAreas),
        JSON.stringify(data.languages ?? []),
        data.notes,
        data.bankName ?? null,
        data.bankAccountNumber ?? null,
        data.bankAccountHolder ?? null,
        data.lineId ?? null,
        data.primaryServiceArea ?? null,
        data.statusLookupTokenHash,
        data.resubmittedFromApplicationId ?? null,
      ],
    );
    return result.insertId;
  }

  async findById(id) {
    const [rows] = await this.pool.query(this.selectApplicationSql('WHERE da.id = ?'), [id]);
    return rows[0] || null;
  }

  async findByIdForUpdate(conn, id) {
    const [rows] = await conn.query(
      `${this.selectApplicationSql('WHERE da.id = ?')} FOR UPDATE`,
      [id],
    );
    return rows[0] || null;
  }

  async findByNumber(applicationNumber) {
    const [rows] = await this.pool.query(
      this.selectApplicationSql('WHERE da.application_number = ? AND da.deleted_at IS NULL'),
      [applicationNumber],
    );
    return rows[0] || null;
  }

  async findByNumberForUpdate(conn, applicationNumber) {
    const [rows] = await conn.query(
      `${this.selectApplicationSql('WHERE da.application_number = ? AND da.deleted_at IS NULL')} FOR UPDATE`,
      [applicationNumber],
    );
    return rows[0] || null;
  }

  async findPendingByEmailForUpdate(conn, email) {
    const [rows] = await conn.query(
      `
        SELECT id, application_number, status
        FROM driver_applications
        WHERE email = ?
          AND status = 'PENDING'
          AND deleted_at IS NULL
        LIMIT 1
        FOR UPDATE
      `,
      [email],
    );
    return rows[0] || null;
  }

  async findPendingByPhoneForUpdate(conn, phone) {
    const [rows] = await conn.query(
      `
        SELECT id, application_number, status
        FROM driver_applications
        WHERE phone = ?
          AND status = 'PENDING'
          AND deleted_at IS NULL
        LIMIT 1
        FOR UPDATE
      `,
      [phone],
    );
    return rows[0] || null;
  }

  async findPendingByPlateForUpdate(conn, plateNumber) {
    const [rows] = await conn.query(
      `
        SELECT id, application_number, status
        FROM driver_applications
        WHERE vehicle_plate_number = ?
          AND status = 'PENDING'
          AND deleted_at IS NULL
        LIMIT 1
        FOR UPDATE
      `,
      [plateNumber],
    );
    return rows[0] || null;
  }

  async findApprovedByEmail(email) {
    const [rows] = await this.pool.query(
      `
        SELECT id, application_number, status
        FROM driver_applications
        WHERE email = ?
          AND status = 'APPROVED'
          AND deleted_at IS NULL
        LIMIT 1
      `,
      [email],
    );
    return rows[0] || null;
  }

  async findActiveUserByEmailForUpdate(conn, email) {
    const [rows] = await conn.query(
      `
        SELECT id, email, role, is_active
        FROM users
        WHERE email = ?
          AND deleted_at IS NULL
        LIMIT 1
        FOR UPDATE
      `,
      [email],
    );
    return rows[0] || null;
  }

  async findActiveUserByPhoneForUpdate(conn, phone) {
    const [rows] = await conn.query(
      `
        SELECT id, email, role, is_active
        FROM users
        WHERE phone = ?
          AND role = 'DRIVER'
          AND deleted_at IS NULL
        LIMIT 1
        FOR UPDATE
      `,
      [phone],
    );
    return rows[0] || null;
  }

  async findVehicleByPlateForUpdate(conn, plateNumber) {
    const [rows] = await conn.query(
      `
        SELECT id, driver_id, plate_number
        FROM driver_vehicles
        WHERE plate_number = ?
          AND deleted_at IS NULL
        LIMIT 1
        FOR UPDATE
      `,
      [plateNumber],
    );
    return rows[0] || null;
  }

  async findVehicleTypeByCode(conn, code) {
    const [rows] = await conn.query(
      `
        SELECT id, code, name
        FROM vehicle_types
        WHERE code = ?
          AND is_active = 1
          AND deleted_at IS NULL
        LIMIT 1
      `,
      [code],
    );
    return rows[0] || null;
  }

  async findVehicleTypeById(conn, id) {
    const [rows] = await conn.query(
      `
        SELECT id, code, name
        FROM vehicle_types
        WHERE id = ?
          AND is_active = 1
          AND deleted_at IS NULL
        LIMIT 1
      `,
      [id],
    );
    return rows[0] || null;
  }

  async listAdmin(filters, pagination) {
    const where = ['da.deleted_at IS NULL'];
    const params = [];

    if (filters.status) {
      where.push('da.status = ?');
      params.push(filters.status);
    }
    if (filters.countryCode) {
      where.push('da.country_code = ?');
      params.push(filters.countryCode);
    }
    if (filters.vehicleTypeCode) {
      where.push('da.vehicle_type_code = ?');
      params.push(filters.vehicleTypeCode);
    }
    if (filters.dateFrom) {
      where.push('da.submitted_at >= ?');
      params.push(`${filters.dateFrom} 00:00:00`);
    }
    if (filters.dateTo) {
      where.push('da.submitted_at < DATE_ADD(?, INTERVAL 1 DAY)');
      params.push(`${filters.dateTo} 00:00:00`);
    }
    if (filters.search) {
      where.push(`(
        da.application_number LIKE ?
        OR da.full_name LIKE ?
        OR da.email LIKE ?
        OR da.phone LIKE ?
        OR da.vehicle_plate_number LIKE ?
      )`);
      const like = `%${filters.search}%`;
      params.push(like, like, like, like, like);
    }

    const whereSql = `WHERE ${where.join(' AND ')}`;
    const [countRows] = await this.pool.query(
      `SELECT COUNT(*) AS total FROM driver_applications da ${whereSql}`,
      params,
    );

    const [rows] = await this.pool.query(
      `
        SELECT
          da.id,
          da.application_number,
          da.status,
          da.email,
          da.full_name,
          da.phone,
          da.primary_service_area,
          da.country_code,
          da.locale,
          da.vehicle_type_code,
          da.vehicle_plate_number,
          da.submitted_at,
          da.reviewed_at,
          da.reviewed_by,
          reviewer.email AS reviewed_by_email
        FROM driver_applications da
        LEFT JOIN users reviewer ON reviewer.id = da.reviewed_by
        ${whereSql}
        ORDER BY da.submitted_at DESC, da.id DESC
        LIMIT ? OFFSET ?
      `,
      [...params, pagination.limit, pagination.offset],
    );

    return {
      items: rows,
      total: Number(countRows[0]?.total ?? 0),
    };
  }

  async insertDriverUser(conn, application, actorUserId) {
    const [result] = await conn.query(
      `
        INSERT INTO users (
          email, password_hash, role, phone, phone_country_code, country_code,
          locale, is_active, email_verified_at
        ) VALUES (?, ?, 'DRIVER', ?, ?, ?, ?, 1, CURRENT_TIMESTAMP)
      `,
      [
        application.email,
        application.password_hash,
        application.phone,
        application.phone_country_code,
        application.country_code,
        application.locale,
      ],
    );

    await conn.query(
      `
        INSERT INTO user_profiles (user_id, display_name, notes)
        VALUES (?, ?, ?)
      `,
      [result.insertId, application.full_name, `Created from driver application by admin ${actorUserId}`],
    );

    return result.insertId;
  }

  async insertDriver(conn, application, vehicleTypeId, userId, actorUserId) {
    const [result] = await conn.query(
      `
        INSERT INTO drivers (
          user_id, name, phone, license_number, status, primary_vehicle_type_id,
          is_online, is_active, created_by, updated_by
        ) VALUES (?, ?, ?, ?, 'OFFLINE', ?, 0, 1, ?, ?)
      `,
      [
        userId,
        application.full_name,
        application.phone,
        application.driving_license_number,
        vehicleTypeId,
        actorUserId,
        actorUserId,
      ],
    );
    return result.insertId;
  }

  async insertDriverVehicle(conn, application, driverId, vehicleTypeId, actorUserId) {
    const modelName = [application.vehicle_make, application.vehicle_model]
      .filter(Boolean)
      .join(' ')
      || application.vehicle_model
      || null;

    const [result] = await conn.query(
      `
        INSERT INTO driver_vehicles (
          driver_id, vehicle_type_id, plate_number, model_name, color,
          is_primary, is_active, created_by, updated_by
        ) VALUES (?, ?, ?, ?, ?, 1, 1, ?, ?)
      `,
      [
        driverId,
        vehicleTypeId,
        application.vehicle_plate_number,
        modelName,
        application.vehicle_color,
        actorUserId,
        actorUserId,
      ],
    );
    return result.insertId;
  }

  async approve(conn, applicationId, { reviewedBy, approvedUserId, approvedDriverId }) {
    await conn.query(
      `
        UPDATE driver_applications
        SET status = 'APPROVED',
            password_hash = NULL,
            rejection_reason = NULL,
            reviewed_by = ?,
            reviewed_at = CURRENT_TIMESTAMP,
            approved_at = CURRENT_TIMESTAMP,
            approved_by = ?,
            approved_user_id = ?,
            approved_driver_id = ?,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
      `,
      [reviewedBy, reviewedBy, approvedUserId, approvedDriverId, applicationId],
    );
  }

  async reject(conn, applicationId, { reviewedBy, rejectionReason, adminNote }) {
    await conn.query(
      `
        UPDATE driver_applications
        SET status = 'REJECTED',
            rejection_reason = ?,
            admin_note = ?,
            reviewed_by = ?,
            reviewed_at = CURRENT_TIMESTAMP,
            rejected_at = CURRENT_TIMESTAMP,
            rejected_by = ?,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
      `,
      [rejectionReason, adminNote, reviewedBy, reviewedBy, applicationId],
    );
  }

  async insertApplicationFile(conn, { applicationId, fileId, category, sortOrder }) {
    await conn.query(
      `
        INSERT INTO driver_application_files (
          driver_application_id, file_id, category, sort_order
        ) VALUES (?, ?, ?, ?)
      `,
      [applicationId, fileId, category, sortOrder],
    );
  }

  async findApplicationFile(applicationId, fileId) {
    const [rows] = await this.pool.query(
      `
        SELECT f.id, f.file_path, f.mime_type, f.original_filename
        FROM driver_application_files daf
        INNER JOIN files f ON f.id = daf.file_id AND f.deleted_at IS NULL
        WHERE daf.driver_application_id = ?
          AND daf.file_id = ?
        LIMIT 1
      `,
      [applicationId, fileId],
    );
    return rows[0] || null;
  }

  async insertAdminNotification(conn, adminUserId, application) {
    await conn.query(
      `
        INSERT INTO notifications (
          recipient_type, user_id, audience_role, event_id, event_name,
          idempotency_key, channel, type, title, body, payload, status, read_at
        ) VALUES (
          'USER', ?, 'ADMIN', ?, 'driver_application.submitted',
          ?, 'IN_APP', 'DRIVER_APPLICATION_SUBMITTED',
          '드라이버 신규 가입 요청',
          ?, ?, 'SENT', NULL
        )
        ON DUPLICATE KEY UPDATE updated_at = updated_at
      `,
      [
        adminUserId,
        `driver-application-${application.id}`,
        `driver-application-submitted:${application.id}:${adminUserId}`,
        `${application.full_name || '신규 기사'}님의 신규 기사 가입 요청이 접수되었습니다.`,
        JSON.stringify({
          applicationId: application.id,
          applicationNumber: application.application_number,
          route: `/admin/driver-applications/${application.id}`,
        }),
      ],
    );
  }

  async insertAuditLog(conn, { userId, action, entityId, payload, ipAddress = null }) {
    await conn.query(
      `
        INSERT INTO audit_logs (user_id, action, entity_type, entity_id, payload, ip_address)
        VALUES (?, ?, 'driver_application', ?, ?, ?)
      `,
      [userId, action, entityId, JSON.stringify(payload ?? {}), ipAddress],
    );
  }

  selectApplicationSql(whereClause) {
    return `
      SELECT
        da.id,
        da.application_number,
        da.status,
        da.email,
        da.password_hash,
        da.full_name,
        da.phone,
        da.phone_country_code,
        da.country_code,
        da.locale,
        da.driving_license_number,
        da.driving_license_country,
        da.driving_license_expiry_date,
        da.years_of_driving_experience,
        da.vehicle_ownership_type,
        da.vehicle_type_code,
        da.vehicle_make,
        da.vehicle_model,
        da.vehicle_year,
        da.vehicle_color,
        da.vehicle_plate_number,
        da.service_areas,
        da.languages,
        da.notes,
        da.bank_name,
        da.bank_account_number,
        da.bank_account_holder,
        da.line_id,
        da.primary_service_area,
        da.personal_data_consent_at,
        da.driver_terms_consent_at,
        da.status_lookup_token_hash,
        da.rejection_reason,
        da.admin_note,
        da.submitted_at,
        da.reviewed_at,
        da.reviewed_by,
        da.approved_user_id,
        da.approved_driver_id,
        da.resubmitted_from_application_id,
        da.created_at,
        da.updated_at,
        COALESCE(
          JSON_ARRAYAGG(
            CASE
              WHEN daf.id IS NULL THEN NULL
              ELSE JSON_OBJECT(
                'id', f.id,
                'category', daf.category,
                'sortOrder', daf.sort_order,
                'originalFilename', f.original_filename,
                'mimeType', f.mime_type,
                'fileSize', f.file_size,
                'url', CONCAT('/api/v1/admin/driver-applications/', da.id, '/files/', f.id)
              )
            END
          ),
          JSON_ARRAY()
        ) AS files_json
      FROM driver_applications da
      LEFT JOIN driver_application_files daf ON daf.driver_application_id = da.id
      LEFT JOIN files f ON f.id = daf.file_id AND f.deleted_at IS NULL
      ${whereClause}
      GROUP BY da.id
    `;
  }
}

module.exports = DriverApplicationRepository;

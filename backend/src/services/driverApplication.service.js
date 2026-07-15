const crypto = require('crypto');
const path = require('path');
const bcrypt = require('bcryptjs');
const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const { generateSecureToken, hashToken } = require('../utils/tokenHash.util');
const { uploadDir } = require('../config/multer');

const REVIEWABLE_STATUS = 'PENDING';
const REJECTED_STATUS = 'REJECTED';
const IMAGE_EXTENSIONS = new Set(['.jpg', '.jpeg', '.png', '.webp']);
const DOCUMENT_EXTENSIONS = new Set(['.jpg', '.jpeg', '.png', '.webp', '.pdf']);
const IMAGE_MIME_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);
const DOCUMENT_MIME_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp', 'application/pdf']);
const GENERIC_MIME_TYPES = new Set(['', 'application/octet-stream']);
const FILE_CATEGORIES = {
  lineQr: 'DRIVER_LINE_QR',
  vehiclePhotos: 'DRIVER_VEHICLE_PHOTO',
  insuranceCertificate: 'DRIVER_INSURANCE_CERTIFICATE',
  vehicleRegistration: 'DRIVER_VEHICLE_REGISTRATION',
  taxCertificate: 'DRIVER_TAX_CERTIFICATE',
};

function parseJson(value, fallback) {
  if (value == null) return fallback;
  if (typeof value === 'object') return value;
  try {
    return JSON.parse(value);
  } catch {
    return fallback;
  }
}

function driverLocalEmail(phone) {
  const digits = String(phone || '').replace(/\D/g, '');
  return `driver+${digits}@driver.local`;
}

class DriverApplicationService {
  constructor(pool, driverApplicationRepository, fileRepository = null, userRepository = null) {
    this.pool = pool;
    this.repository = driverApplicationRepository;
    this.fileRepository = fileRepository;
    this.userRepository = userRepository;
  }

  normalizeInput(input) {
    const phone = input.phone.trim();
    return {
      ...input,
      email: input.email?.trim().toLowerCase() || driverLocalEmail(phone),
      fullName: input.fullName.trim(),
      phone,
      phoneCountryCode: input.phoneCountryCode?.trim() || null,
      countryCode: input.countryCode?.trim().toUpperCase() || null,
      locale: input.locale || 'ko',
      drivingLicenseNumber: input.drivingLicenseNumber.trim(),
      drivingLicenseCountry: input.drivingLicenseCountry?.trim().toUpperCase() || null,
      vehicleOwnershipType: input.vehicleOwnershipType,
      vehicleTypeCode: input.vehicleTypeCode.trim().toUpperCase(),
      vehicleMake: input.vehicleMake?.trim() || null,
      vehicleModel: input.vehicleModel?.trim() || null,
      vehicleColor: input.vehicleColor?.trim() || null,
      vehiclePlateNumber: input.vehiclePlateNumber.trim().replace(/\s+/gu, ' '),
      serviceAreas: input.serviceAreas,
      languages: input.languages ?? [],
      notes: input.notes?.trim() || null,
      bankName: input.bankName?.trim() || null,
      bankAccountNumber: input.bankAccountNumber?.trim() || null,
      bankAccountHolder: input.bankAccountHolder?.trim() || null,
      lineId: input.lineId?.trim() || null,
      primaryServiceArea: input.primaryServiceArea?.trim() || input.serviceAreas?.[0] || null,
    };
  }

  parsePagination(query) {
    const page = Math.max(Number(query.page) || 1, 1);
    const limit = Math.min(Math.max(Number(query.limit ?? query.page_size) || 20, 1), 100);
    return { page, limit, offset: (page - 1) * limit };
  }

  parseFilters(query) {
    return {
      view: ['needs_action', 'approved', 'closed', 'all'].includes(query.view)
        ? query.view
        : 'needs_action',
      status: query.status || null,
      countryCode: query.countryCode?.trim().toUpperCase() || null,
      vehicleTypeCode: query.vehicleTypeCode?.trim().toUpperCase() || null,
      dateFrom: query.dateFrom || null,
      dateTo: query.dateTo || null,
      search: query.search?.trim() || null,
    };
  }

  generateApplicationNumber() {
    const now = new Date();
    const date = now.toISOString().slice(2, 10).replace(/-/g, '');
    const suffix = crypto.randomBytes(4).toString('hex').toUpperCase();
    return `DA${date}${suffix}`;
  }

  tokenHashMatches(storedHash, rawToken) {
    if (!storedHash || !rawToken) return false;
    const candidateHash = hashToken(rawToken);
    const stored = Buffer.from(storedHash, 'hex');
    const candidate = Buffer.from(candidateHash, 'hex');
    return stored.length === candidate.length && crypto.timingSafeEqual(stored, candidate);
  }

  conflict(message) {
    throw new AppError(message, {
      statusCode: HTTP_STATUS.CONFLICT,
      errorCode: ERROR_CODES.DUPLICATE_BOOKING,
    });
  }

  validation(message, field) {
    throw new AppError(message, {
      statusCode: HTTP_STATUS.BAD_REQUEST,
      errorCode: ERROR_CODES.VALIDATION_ERROR,
      errors: field ? [{ field, message }] : undefined,
    });
  }

  invalidFileType({ field, file, message, allowedExtensions }) {
    const safeName = path.basename(String(file?.originalname || file?.filename || '').split(/[?#]/)[0]);
    throw new AppError('Invalid file type', {
      statusCode: HTTP_STATUS.BAD_REQUEST,
      errorCode: ERROR_CODES.INVALID_FILE_TYPE,
      errors: [{
        field,
        fileName: safeName || undefined,
        mimeType: file?.mimetype || undefined,
        allowedExtensions: Array.from(allowedExtensions).map((ext) => ext.slice(1)),
        message,
      }],
    });
  }

  normalizeFiles(files = {}) {
    return {
      lineQr: files.lineQr?.[0] ? [files.lineQr[0]] : [],
      vehiclePhotos: files.vehiclePhotos ?? [],
      insuranceCertificate: files.insuranceCertificate?.[0] ? [files.insuranceCertificate[0]] : [],
      vehicleRegistration: files.vehicleRegistration?.[0] ? [files.vehicleRegistration[0]] : [],
      taxCertificate: files.taxCertificate?.[0] ? [files.taxCertificate[0]] : [],
    };
  }

  validateFile(file, { imageOnly = false, field }) {
    const safeName = path.basename(String(file.originalname || file.filename || '').split(/[?#]/)[0]);
    const ext = path.extname(safeName).toLowerCase();
    const allowed = imageOnly ? IMAGE_EXTENSIONS : DOCUMENT_EXTENSIONS;
    const allowedMimes = imageOnly ? IMAGE_MIME_TYPES : DOCUMENT_MIME_TYPES;
    const mime = String(file.mimetype || '').toLowerCase();
    if (!allowed.has(ext)) {
      this.invalidFileType({
        field,
        file,
        allowedExtensions: allowed,
        message: 'Unsupported file extension',
      });
    }
    if (!GENERIC_MIME_TYPES.has(mime) && !allowedMimes.has(mime)) {
      this.invalidFileType({
        field,
        file,
        allowedExtensions: allowed,
        message: 'Unsupported file MIME type',
      });
    }
  }

  validateRequiredFiles(files) {
    const normalized = this.normalizeFiles(files);
    if (normalized.vehiclePhotos.length > 0) {
      if (normalized.vehiclePhotos.length < 3) {
        this.validation('At least 3 vehicle photos are required', 'vehiclePhotos');
      }
      if (normalized.vehiclePhotos.length > 6) {
        this.validation('At most 6 vehicle photos are allowed', 'vehiclePhotos');
      }
      for (const key of ['lineQr', 'insuranceCertificate', 'vehicleRegistration', 'taxCertificate']) {
        if (normalized[key].length !== 1) {
          this.validation(`${key} is required`, key);
        }
      }
    }
    for (const [key, list] of Object.entries(normalized)) {
      list.forEach((file) => this.validateFile(file, {
        imageOnly: key === 'lineQr' || key === 'vehiclePhotos',
        field: key,
      }));
    }
    return normalized;
  }

  invalidTransition(message) {
    throw new AppError(message, {
      statusCode: HTTP_STATUS.UNPROCESSABLE,
      errorCode: ERROR_CODES.INVALID_STATUS_TRANSITION,
    });
  }

  notFound(message = 'Driver application not found') {
    throw new AppError(message, {
      statusCode: HTTP_STATUS.NOT_FOUND,
      errorCode: ERROR_CODES.NOT_FOUND,
    });
  }

  async ensureCanSubmit(conn, input, { allowRejectedSourceId = null } = {}) {
    const existingUser = await this.repository.findActiveUserByEmailForUpdate(conn, input.email);
    if (existingUser) {
      this.conflict('A driver application cannot be submitted for this email');
    }

    const existingUserPhone = typeof this.repository.findActiveUserByPhoneForUpdate === 'function'
      ? await this.repository.findActiveUserByPhoneForUpdate(conn, input.phone)
      : null;
    if (existingUserPhone) {
      this.conflict('A driver account already exists for this phone number');
    }

    const pendingPhone = typeof this.repository.findPendingByPhoneForUpdate === 'function'
      ? await this.repository.findPendingByPhoneForUpdate(conn, input.phone)
      : null;
    if (pendingPhone) {
      this.conflict('A pending driver application already exists for this phone number');
    }

    const pendingEmail = await this.repository.findPendingByEmailForUpdate(conn, input.email);
    if (pendingEmail) {
      this.conflict('A pending driver application already exists for this email');
    }

    const approvedEmail = await this.repository.findApprovedByEmail(input.email);
    if (approvedEmail) {
      this.conflict('A driver application has already been approved for this email');
    }

    const pendingPlate = await this.repository.findPendingByPlateForUpdate(
      conn,
      input.vehiclePlateNumber,
    );
    if (pendingPlate) {
      this.conflict('A pending driver application already exists for this vehicle plate');
    }

    const existingVehicle = await this.repository.findVehicleByPlateForUpdate(
      conn,
      input.vehiclePlateNumber,
    );
    if (existingVehicle) {
      this.conflict('This vehicle plate is already registered');
    }

    const vehicleType = input.vehicleTypeCode.startsWith('#') && typeof this.repository.findVehicleTypeById === 'function'
      ? await this.repository.findVehicleTypeById(conn, Number(input.vehicleTypeCode.slice(1)))
      : await this.repository.findVehicleTypeByCode(conn, input.vehicleTypeCode);
    if (!vehicleType) {
      throw new AppError('Vehicle type is not supported', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
        errors: [{ field: 'vehicleTypeCode', message: 'Vehicle type is not supported' }],
      });
    }

    if (allowRejectedSourceId) {
      const source = await this.repository.findByIdForUpdate(conn, allowRejectedSourceId);
      if (!source || source.status !== REJECTED_STATUS) {
        this.invalidTransition('Only rejected applications can be resubmitted');
      }
    }

    return vehicleType;
  }

  async saveApplicationFiles(conn, applicationId, files) {
    if (!this.fileRepository) return;
    const normalized = this.validateRequiredFiles(files);
    for (const [field, list] of Object.entries(normalized)) {
      for (const [index, file] of list.entries()) {
        const relativePath = path.relative(uploadDir, file.path).replace(/\\/g, '/');
        const fileId = await this.fileRepository.insert(conn, {
          entityType: 'driver_application',
          entityId: applicationId,
          filePath: relativePath,
          mimeType: file.mimetype,
          fileSize: file.size,
          originalFilename: path.basename(file.originalname || file.filename || 'upload'),
        });
        await this.repository.insertApplicationFile(conn, {
          applicationId,
          fileId,
          category: FILE_CATEGORIES[field],
          sortOrder: index + 1,
        });
      }
    }
  }

  async createAdminNotifications(conn, application) {
    if (!this.userRepository || typeof this.repository.insertAdminNotification !== 'function') return;
    const admins = await this.userRepository.findActiveByRoles(['ADMIN', 'SUPER_ADMIN']);
    for (const admin of admins) {
      await this.repository.insertAdminNotification(conn, admin.id, application);
    }
  }

  async submit(input, options = {}) {
    const normalized = this.normalizeInput(input);
    const passwordHash = await bcrypt.hash(normalized.password, 12);
    const statusToken = generateSecureToken();
    const conn = await this.pool.getConnection();

    try {
      await conn.beginTransaction();
      const vehicleType = await this.ensureCanSubmit(conn, normalized);

      const applicationNumber = this.generateApplicationNumber();
      const id = await this.repository.create(conn, {
        ...normalized,
        vehicleTypeCode: vehicleType.code,
        applicationNumber,
        passwordHash,
        statusLookupTokenHash: hashToken(statusToken),
      });
      await this.saveApplicationFiles(conn, id, options.files);
      await this.createAdminNotifications(conn, {
        id,
        application_number: applicationNumber,
        full_name: normalized.fullName,
      });

      await conn.commit();

      const application = await this.repository.findById(id);
      return {
        applicationNumber: application.application_number,
        status: application.status,
        statusToken,
        submittedAt: application.submitted_at,
      };
    } catch (err) {
      await conn.rollback();
      if (err.code === 'ER_DUP_ENTRY') {
        this.conflict('A duplicate driver application was detected');
      }
      throw err;
    } finally {
      conn.release();
    }
  }

  async status({ applicationNumber, token }) {
    const application = await this.repository.findByNumber(applicationNumber);
    if (!application || !this.tokenHashMatches(application.status_lookup_token_hash, token)) {
      this.notFound();
    }

    return {
      applicationNumber: application.application_number,
      status: application.status,
      submittedAt: application.submitted_at,
      reviewedAt: application.reviewed_at,
      rejectionReason: application.status === REJECTED_STATUS ? application.rejection_reason : null,
    };
  }

  async resubmit(applicationNumber, token, input, options = {}) {
    const normalized = this.normalizeInput(input);
    const passwordHash = await bcrypt.hash(normalized.password, 12);
    const newStatusToken = generateSecureToken();
    const conn = await this.pool.getConnection();

    try {
      await conn.beginTransaction();
      const source = await this.repository.findByNumberForUpdate(conn, applicationNumber);
      if (!source || !this.tokenHashMatches(source.status_lookup_token_hash, token)) {
        this.notFound();
      }
      if (source.status !== REJECTED_STATUS) {
        this.invalidTransition('Only rejected applications can be resubmitted');
      }

      const vehicleType = await this.ensureCanSubmit(conn, normalized, { allowRejectedSourceId: source.id });

      const newApplicationNumber = this.generateApplicationNumber();
      const id = await this.repository.create(conn, {
        ...normalized,
        vehicleTypeCode: vehicleType.code,
        applicationNumber: newApplicationNumber,
        passwordHash,
        statusLookupTokenHash: hashToken(newStatusToken),
        resubmittedFromApplicationId: source.id,
      });
      await this.saveApplicationFiles(conn, id, options.files);
      await this.createAdminNotifications(conn, {
        id,
        application_number: newApplicationNumber,
        full_name: normalized.fullName,
      });

      await conn.commit();
      const application = await this.repository.findById(id);
      return {
        applicationNumber: application.application_number,
        status: application.status,
        statusToken: newStatusToken,
        submittedAt: application.submitted_at,
      };
    } catch (err) {
      await conn.rollback();
      if (err.code === 'ER_DUP_ENTRY') {
        this.conflict('A duplicate driver application was detected');
      }
      throw err;
    } finally {
      conn.release();
    }
  }

  async listAdmin(query) {
    const pagination = this.parsePagination(query);
    const filters = this.parseFilters(query);
    const result = await this.repository.listAdmin(filters, pagination);
    return {
      page: pagination.page,
      pageSize: pagination.limit,
      total: result.total,
      items: result.items.map((row) => this.mapAdminListItem(row)),
    };
  }

  async getAdminDetail(id) {
    const application = await this.repository.findById(id);
    if (!application) {
      this.notFound();
    }
    return this.mapAdminDetail(application);
  }

  async getAdminFile(applicationId, fileId) {
    const file = await this.repository.findApplicationFile(applicationId, fileId);
    if (!file) this.notFound('Driver application file not found');
    return {
      filePath: file.file_path,
      mimeType: file.mime_type,
      originalFilename: file.original_filename,
    };
  }

  async approve(id, body, actor, requestMeta = {}) {
    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      const application = await this.repository.findByIdForUpdate(conn, id);
      if (!application) {
        this.notFound();
      }
      if (application.status !== REVIEWABLE_STATUS) {
        this.invalidTransition('Only pending applications can be approved');
      }
      if (!application.password_hash) {
        this.invalidTransition('Application password is no longer available');
      }

      const existingUser = await this.repository.findActiveUserByEmailForUpdate(
        conn,
        application.email,
      );
      if (existingUser) {
        this.conflict('A user already exists for this email');
      }

      const existingVehicle = await this.repository.findVehicleByPlateForUpdate(
        conn,
        application.vehicle_plate_number,
      );
      if (existingVehicle) {
        this.conflict('This vehicle plate is already registered');
      }

      const vehicleType = await this.repository.findVehicleTypeByCode(
        conn,
        application.vehicle_type_code,
      );
      if (!vehicleType) {
        this.invalidTransition('Vehicle type is no longer available');
      }

      const userId = await this.repository.insertDriverUser(conn, application, actor.id);
      const driverId = await this.repository.insertDriver(
        conn,
        application,
        vehicleType.id,
        userId,
        actor.id,
      );
      const vehicleId = await this.repository.insertDriverVehicle(
        conn,
        application,
        driverId,
        vehicleType.id,
        actor.id,
      );

      await this.repository.approve(conn, application.id, {
        reviewedBy: actor.id,
        approvedUserId: userId,
        approvedDriverId: driverId,
      });
      await this.repository.insertAuditLog(conn, {
        userId: actor.id,
        action: 'driver_application.approved',
        entityId: application.id,
        ipAddress: requestMeta.ipAddress,
        payload: {
          applicationNumber: application.application_number,
          approvedUserId: userId,
          approvedDriverId: driverId,
          vehicleId,
          adminNote: body.adminNote ?? null,
        },
      });

      await conn.commit();

      return {
        applicationNumber: application.application_number,
        status: 'APPROVED',
        approvedUserId: userId,
        approvedDriverId: driverId,
        vehicleId,
      };
    } catch (err) {
      await conn.rollback();
      if (err.code === 'ER_DUP_ENTRY') {
        this.conflict('A duplicate user or vehicle was detected during approval');
      }
      throw err;
    } finally {
      conn.release();
    }
  }

  async reject(id, input, actor, requestMeta = {}) {
    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      const application = await this.repository.findByIdForUpdate(conn, id);
      if (!application) {
        this.notFound();
      }
      if (application.status !== REVIEWABLE_STATUS) {
        this.invalidTransition('Only pending applications can be rejected');
      }

      await this.repository.reject(conn, application.id, {
        reviewedBy: actor.id,
        rejectionReason: input.rejectionReason,
        adminNote: input.adminNote ?? null,
      });
      await this.repository.insertAuditLog(conn, {
        userId: actor.id,
        action: 'driver_application.rejected',
        entityId: application.id,
        ipAddress: requestMeta.ipAddress,
        payload: {
          applicationNumber: application.application_number,
          hasAdminNote: Boolean(input.adminNote),
        },
      });

      await conn.commit();
      return {
        applicationNumber: application.application_number,
        status: 'REJECTED',
        reviewedBy: actor.id,
      };
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }

  mapAdminListItem(row) {
    return {
      id: row.id,
      applicationNumber: row.application_number,
      status: row.status,
      email: row.email,
      fullName: row.full_name,
      phone: row.phone,
      countryCode: row.country_code,
      locale: row.locale,
      vehicleTypeCode: row.vehicle_type_code,
      vehiclePlateNumber: row.vehicle_plate_number,
      primaryServiceArea: row.primary_service_area,
      submittedAt: row.submitted_at,
      reviewedAt: row.reviewed_at,
      reviewedBy: row.reviewed_by
        ? { id: row.reviewed_by, email: row.reviewed_by_email ?? null }
        : null,
    };
  }

  mapAdminDetail(row) {
    return {
      id: row.id,
      applicationNumber: row.application_number,
      status: row.status,
      email: row.email,
      fullName: row.full_name,
      phone: row.phone,
      phoneCountryCode: row.phone_country_code,
      countryCode: row.country_code,
      locale: row.locale,
      drivingLicenseNumber: row.driving_license_number,
      drivingLicenseCountry: row.driving_license_country,
      drivingLicenseExpiryDate: row.driving_license_expiry_date,
      yearsOfDrivingExperience: row.years_of_driving_experience,
      vehicleOwnershipType: row.vehicle_ownership_type,
      vehicleTypeCode: row.vehicle_type_code,
      vehicleMake: row.vehicle_make,
      vehicleModel: row.vehicle_model,
      vehicleYear: row.vehicle_year,
      vehicleColor: row.vehicle_color,
      vehiclePlateNumber: row.vehicle_plate_number,
      serviceAreas: parseJson(row.service_areas, []),
      languages: parseJson(row.languages, []),
      notes: row.notes,
      bankName: row.bank_name,
      bankAccountNumber: row.bank_account_number,
      bankAccountHolder: row.bank_account_holder,
      lineId: row.line_id,
      primaryServiceArea: row.primary_service_area,
      files: parseJson(row.files_json, []),
      personalDataConsentAt: row.personal_data_consent_at,
      driverTermsConsentAt: row.driver_terms_consent_at,
      rejectionReason: row.rejection_reason,
      adminNote: row.admin_note,
      submittedAt: row.submitted_at,
      reviewedAt: row.reviewed_at,
      reviewedBy: row.reviewed_by,
      approvedUserId: row.approved_user_id,
      approvedDriverId: row.approved_driver_id,
      resubmittedFromApplicationId: row.resubmitted_from_application_id,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }

}

module.exports = DriverApplicationService;

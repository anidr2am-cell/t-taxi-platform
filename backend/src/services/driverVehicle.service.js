const path = require('path');
const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const { uploadDir } = require('../config/multer');

const IMAGE_EXTENSIONS = new Set(['.jpg', '.jpeg', '.png', '.webp']);
const DOCUMENT_EXTENSIONS = new Set(['.jpg', '.jpeg', '.png', '.webp', '.pdf']);
const IMAGE_MIME_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);
const DOCUMENT_MIME_TYPES = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'application/pdf',
]);
const GENERIC_MIME_TYPES = new Set(['', 'application/octet-stream']);

const FILE_CATEGORIES = {
  vehiclePhotos: 'DRIVER_VEHICLE_PHOTO',
  insuranceCertificate: 'DRIVER_INSURANCE_CERTIFICATE',
  vehicleRegistration: 'DRIVER_VEHICLE_REGISTRATION',
  taxCertificate: 'DRIVER_TAX_CERTIFICATE',
};

const REVIEWABLE_STATUS = 'PENDING';

function parseJson(value, fallback) {
  if (value == null) return fallback;
  if (typeof value === 'object') return value;
  try {
    return JSON.parse(value);
  } catch {
    return fallback;
  }
}

class DriverVehicleService {
  constructor(pool, driverRepository, vehicleRepository, fileRepository) {
    this.pool = pool;
    this.driverRepository = driverRepository;
    this.vehicleRepository = vehicleRepository;
    this.fileRepository = fileRepository;
  }

  validation(message, field) {
    throw new AppError(message, {
      statusCode: HTTP_STATUS.BAD_REQUEST,
      errorCode: ERROR_CODES.VALIDATION_ERROR,
      errors: field ? [{ field, message }] : undefined,
    });
  }

  conflict(message, errorCode = ERROR_CODES.VEHICLE_PLATE_ALREADY_REGISTERED) {
    throw new AppError(message, {
      statusCode: HTTP_STATUS.CONFLICT,
      errorCode,
    });
  }

  notFound(message = 'Driver not found', errorCode = ERROR_CODES.DRIVER_NOT_FOUND) {
    throw new AppError(message, {
      statusCode: HTTP_STATUS.NOT_FOUND,
      errorCode,
    });
  }

  vehicleNotFound() {
    this.notFound('Driver vehicle not found', ERROR_CODES.DRIVER_VEHICLE_NOT_FOUND);
  }

  invalidTransition(message) {
    throw new AppError(message, {
      statusCode: HTTP_STATUS.CONFLICT,
      errorCode: ERROR_CODES.INVALID_STATUS_TRANSITION,
    });
  }

  parsePagination(query = {}) {
    const page = Math.max(1, Number(query.page) || 1);
    const limit = Math.min(100, Math.max(1, Number(query.limit || query.page_size) || 20));
    return {
      page,
      limit,
      offset: (page - 1) * limit,
    };
  }

  parseAdminFilters(query = {}) {
    const search = query.search == null ? null : String(query.search).trim();
    return {
      status: query.status || null,
      search: search || null,
    };
  }

  parseFiles(filesJson) {
    const files = parseJson(filesJson, []);
    if (!Array.isArray(files)) return [];
    return files
      .filter((file) => file && file.id != null)
      .map((file) => ({
        id: Number(file.id),
        category: file.category,
        sortOrder: Number(file.sortOrder ?? 0),
        originalFilename: file.originalFilename || null,
        mimeType: file.mimeType || null,
        fileSize: file.fileSize == null ? null : Number(file.fileSize),
        url: file.url || null,
      }))
      .sort((a, b) => a.sortOrder - b.sortOrder || a.id - b.id);
  }

  mapAdminVehicle(row) {
    return {
      id: Number(row.id),
      driverId: Number(row.driver_id),
      driverUserId: Number(row.driver_user_id),
      driverName: row.driver_name,
      driverPhone: row.driver_phone || null,
      vehicleTypeId: Number(row.vehicle_type_id),
      vehicleTypeCode: row.vehicle_type_code,
      vehicleTypeName: row.vehicle_type_name,
      plateNumber: row.plate_number,
      modelName: row.model_name,
      color: row.color,
      isPrimary: Number(row.is_primary) === 1,
      isActive: Number(row.is_active) === 1,
      approvalStatus: row.approval_status || 'APPROVED',
      rejectionReason: row.rejection_reason || null,
      submittedAt: row.created_at,
      updatedAt: row.updated_at,
      files: this.parseFiles(row.files_json),
    };
  }

  normalizePlate(plateNumber) {
    const value = String(plateNumber ?? '').trim().replace(/\s+/gu, ' ');
    if (!value) {
      this.validation('Plate number is required', 'plateNumber');
    }
    if (value.length > 20) {
      this.validation('Plate number is too long', 'plateNumber');
    }
    return value;
  }

  normalizeOptionalText(value, field, maxLen) {
    if (value == null || value === '') return null;
    const text = String(value).trim();
    if (!text) return null;
    if (text.length > maxLen) {
      this.validation(`${field} is too long`, field);
    }
    return text;
  }

  asFileList(value) {
    if (!value) return [];
    return Array.isArray(value) ? value : [value];
  }

  normalizeFiles(files = {}) {
    return {
      vehiclePhotos: this.asFileList(files.vehiclePhotos),
      insuranceCertificate: this.asFileList(files.insuranceCertificate),
      vehicleRegistration: this.asFileList(files.vehicleRegistration),
      taxCertificate: this.asFileList(files.taxCertificate),
    };
  }

  validateFile(file, { imageOnly = false, field } = {}) {
    if (!file) {
      this.validation('File is required', field);
    }
    const ext = path.extname(String(file.originalname || file.filename || '')).toLowerCase();
    const mime = String(file.mimetype || '').toLowerCase();
    const allowedExt = imageOnly ? IMAGE_EXTENSIONS : DOCUMENT_EXTENSIONS;
    const allowedMime = imageOnly ? IMAGE_MIME_TYPES : DOCUMENT_MIME_TYPES;
    if (!allowedExt.has(ext)) {
      throw new AppError('Invalid file type', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.INVALID_FILE_TYPE,
      });
    }
    if (!GENERIC_MIME_TYPES.has(mime) && !allowedMime.has(mime)) {
      throw new AppError('Invalid file type', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.INVALID_FILE_TYPE,
      });
    }
  }

  validateRequiredFiles(files) {
    const normalized = this.normalizeFiles(files);
    if (normalized.vehiclePhotos.length < 3) {
      this.validation('At least 3 vehicle photos are required', 'vehiclePhotos');
    }
    if (normalized.vehiclePhotos.length > 6) {
      this.validation('At most 6 vehicle photos are allowed', 'vehiclePhotos');
    }
    for (const key of ['insuranceCertificate', 'vehicleRegistration']) {
      if (normalized[key].length !== 1) {
        this.validation(`${key} is required`, key);
      }
    }
    if (normalized.taxCertificate.length > 1) {
      this.validation('At most 1 tax certificate is allowed', 'taxCertificate');
    }
    for (const [key, list] of Object.entries(normalized)) {
      list.forEach((file) => this.validateFile(file, {
        imageOnly: key === 'vehiclePhotos',
        field: key,
      }));
    }
    return normalized;
  }

  mapVehicle(row) {
    return {
      id: Number(row.id),
      vehicleTypeId: Number(row.vehicle_type_id),
      vehicleTypeCode: row.vehicle_type_code,
      vehicleTypeName: row.vehicle_type_name,
      plateNumber: row.plate_number,
      modelName: row.model_name,
      color: row.color,
      isPrimary: Number(row.is_primary) === 1,
      isActive: Number(row.is_active) === 1,
      approvalStatus: row.approval_status || 'APPROVED',
      rejectionReason: row.rejection_reason || null,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
      documentCounts: {
        vehiclePhotos: Number(row.photo_count || 0),
        insuranceCertificate: Number(row.insurance_count || 0),
        vehicleRegistration: Number(row.registration_count || 0),
        taxCertificate: Number(row.tax_count || 0),
      },
    };
  }

  async listVehicles(driverUserId) {
    const driver = await this.driverRepository.findByUserId(driverUserId);
    if (!driver || !driver.is_active || driver.user_is_active === 0) {
      this.notFound();
    }
    const rows = await this.driverRepository.listVehiclesByDriverId(driver.id);
    return {
      items: rows.map((row) => this.mapVehicle(row)),
    };
  }

  async saveVehicleFiles(conn, vehicleId, files, actorUserId) {
    const normalized = this.validateRequiredFiles(files);
    for (const [field, list] of Object.entries(normalized)) {
      for (const [index, file] of list.entries()) {
        const relativePath = path.relative(uploadDir, file.path).replace(/\\/g, '/');
        const fileId = await this.fileRepository.insert(conn, {
          entityType: 'driver_vehicle',
          entityId: vehicleId,
          filePath: relativePath,
          mimeType: file.mimetype,
          fileSize: file.size,
          originalFilename: path.basename(file.originalname || file.filename || 'upload'),
          uploadedByUserId: actorUserId,
          createdBy: actorUserId,
          updatedBy: actorUserId,
        });
        await this.driverRepository.insertVehicleFile(conn, {
          vehicleId,
          fileId,
          category: FILE_CATEGORIES[field],
          sortOrder: index + 1,
        });
      }
    }
  }

  async createVehicle(driverUserId, input, files = {}) {
    const plateNumber = this.normalizePlate(input.plateNumber);
    const modelName = this.normalizeOptionalText(input.modelName, 'modelName', 100);
    const color = this.normalizeOptionalText(input.color, 'color', 30);
    const vehicleTypeId = Number(input.vehicleTypeId);
    if (!Number.isInteger(vehicleTypeId) || vehicleTypeId <= 0) {
      this.validation('vehicleTypeId is required', 'vehicleTypeId');
    }

    // Validate files before opening a DB transaction.
    this.validateRequiredFiles(files);

    const vehicleType = await this.vehicleRepository.findTypeById(vehicleTypeId);
    if (!vehicleType) {
      this.validation('Vehicle type is not supported', 'vehicleTypeId');
    }

    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      const driver = await this.driverRepository.findByUserIdForUpdate(conn, driverUserId);
      if (!driver || !driver.is_active || driver.user_is_active === 0) {
        this.notFound();
      }

      const existing = await this.driverRepository.findVehicleByPlateForUpdate(conn, plateNumber);
      if (existing) {
        this.conflict('This vehicle plate is already registered');
      }

      let vehicleId;
      try {
        vehicleId = await this.driverRepository.insertPendingVehicle(conn, {
          driverId: driver.id,
          vehicleTypeId: vehicleType.id,
          plateNumber,
          modelName,
          color,
          actorUserId: driverUserId,
        });
      } catch (err) {
        if (err && err.code === 'ER_DUP_ENTRY') {
          this.conflict('This vehicle plate is already registered');
        }
        throw err;
      }

      await this.saveVehicleFiles(conn, vehicleId, files, driverUserId);
      await conn.commit();

      const created = await this.driverRepository.findVehicleByIdForDriver(driver.id, vehicleId);
      return this.mapVehicle(created);
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }

  async listAdmin(query = {}) {
    const pagination = this.parsePagination(query);
    const filters = this.parseAdminFilters(query);
    const result = await this.driverRepository.listVehiclesForAdmin(filters, pagination);
    return {
      page: pagination.page,
      pageSize: pagination.limit,
      total: result.total,
      items: result.items.map((row) => this.mapAdminVehicle(row)),
    };
  }

  async getAdminDetail(id) {
    const vehicle = await this.driverRepository.findVehicleByIdForAdmin(id);
    if (!vehicle) this.vehicleNotFound();
    return this.mapAdminVehicle(vehicle);
  }

  async getAdminFile(vehicleId, fileId) {
    const file = await this.driverRepository.findVehicleFile(vehicleId, fileId);
    if (!file) {
      this.notFound('Driver vehicle file not found', ERROR_CODES.FILE_NOT_FOUND);
    }
    return {
      filePath: file.file_path,
      mimeType: file.mime_type,
      originalFilename: file.original_filename,
    };
  }

  async approve(id, body = {}, actor, requestMeta = {}) {
    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      const vehicle = await this.driverRepository.findVehicleByIdForUpdate(conn, id);
      if (!vehicle) this.vehicleNotFound();
      if (vehicle.approval_status !== REVIEWABLE_STATUS) {
        this.invalidTransition('Only pending vehicles can be approved');
      }

      await this.driverRepository.approveVehicle(conn, vehicle.id, actor.id);
      await this.driverRepository.insertVehicleAuditLog(conn, {
        userId: actor.id,
        action: 'driver_vehicle.approved',
        entityId: vehicle.id,
        ipAddress: requestMeta.ipAddress,
        payload: {
          driverId: vehicle.driver_id,
          plateNumber: vehicle.plate_number,
          adminNote: body.adminNote ?? null,
        },
      });

      await conn.commit();
      return {
        id: Number(vehicle.id),
        approvalStatus: 'APPROVED',
        isActive: true,
        reviewedBy: actor.id,
      };
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }

  async reject(id, input, actor, requestMeta = {}) {
    const rejectionReason = String(input.rejectionReason || '').trim();
    if (!rejectionReason) {
      this.validation('rejectionReason is required', 'rejectionReason');
    }

    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      const vehicle = await this.driverRepository.findVehicleByIdForUpdate(conn, id);
      if (!vehicle) this.vehicleNotFound();
      if (vehicle.approval_status !== REVIEWABLE_STATUS) {
        this.invalidTransition('Only pending vehicles can be rejected');
      }

      await this.driverRepository.rejectVehicle(conn, vehicle.id, {
        rejectionReason,
        actorUserId: actor.id,
      });
      await this.driverRepository.insertVehicleAuditLog(conn, {
        userId: actor.id,
        action: 'driver_vehicle.rejected',
        entityId: vehicle.id,
        ipAddress: requestMeta.ipAddress,
        payload: {
          driverId: vehicle.driver_id,
          plateNumber: vehicle.plate_number,
          hasAdminNote: Boolean(input.adminNote),
        },
      });

      await conn.commit();
      return {
        id: Number(vehicle.id),
        approvalStatus: 'REJECTED',
        isActive: false,
        rejectionReason,
        reviewedBy: actor.id,
      };
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }
}

module.exports = DriverVehicleService;

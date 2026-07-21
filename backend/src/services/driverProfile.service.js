const fs = require('fs');
const path = require('path');
const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const { uploadDir } = require('../config/multer');

const IMAGE_EXTENSIONS = new Set(['.jpg', '.jpeg', '.png', '.webp']);
const IMAGE_MIME_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);
const GENERIC_MIME_TYPES = new Set(['', 'application/octet-stream']);
const MIN_VEHICLE_YEAR = 1990;
const MAX_VEHICLE_YEAR = new Date().getFullYear() + 1;

class DriverProfileService {
  constructor(
    pool,
    driverRepository,
    vehicleRepository,
    fileRepository,
    driverApplicationRepository = null,
  ) {
    this.pool = pool;
    this.driverRepository = driverRepository;
    this.vehicleRepository = vehicleRepository;
    this.fileRepository = fileRepository;
    this.driverApplicationRepository = driverApplicationRepository;
  }

  validation(message, field) {
    throw new AppError(message, {
      statusCode: HTTP_STATUS.BAD_REQUEST,
      errorCode: ERROR_CODES.VALIDATION_ERROR,
      errors: field ? [{ field, message }] : undefined,
    });
  }

  notFound() {
    throw new AppError('Driver not found', {
      statusCode: HTTP_STATUS.NOT_FOUND,
      errorCode: ERROR_CODES.DRIVER_NOT_FOUND,
    });
  }

  normalizePhone(phone) {
    const value = String(phone ?? '').trim();
    if (!value) {
      this.validation('Phone number is required', 'phone');
    }
    if (!/^\+?[0-9()\-\s]{8,20}$/.test(value)) {
      this.validation('Invalid phone number format', 'phone');
    }
    return value.replace(/\s+/g, ' ');
  }

  normalizeName(name) {
    const value = String(name ?? '').trim();
    if (!value) {
      this.validation('Name is required', 'name');
    }
    if (value.length > 100) {
      this.validation('Name is too long', 'name');
    }
    return value;
  }

  normalizeVehicleYear(raw) {
    if (raw == null || raw === '') return null;
    const year = Number(raw);
    if (!Number.isInteger(year) || year < MIN_VEHICLE_YEAR || year > MAX_VEHICLE_YEAR) {
      this.validation('Invalid vehicle year', 'vehicleYear');
    }
    return year;
  }

  validateImageFile(file, field) {
    if (!file) {
      this.validation('Image file is required', field);
    }
    const ext = path.extname(String(file.originalname || file.filename || '')).toLowerCase();
    const mime = String(file.mimetype || '').toLowerCase();
    if (!IMAGE_EXTENSIONS.has(ext)) {
      throw new AppError('Invalid file type', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.INVALID_FILE_TYPE,
      });
    }
    if (!GENERIC_MIME_TYPES.has(mime) && !IMAGE_MIME_TYPES.has(mime)) {
      throw new AppError('Invalid file type', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.INVALID_FILE_TYPE,
      });
    }
  }

  safeStoredFilename(file, fallback = 'image') {
    const ext = path.extname(file.originalname || '').toLowerCase().replace(/[^a-z0-9.]/g, '');
    const allowedExt = IMAGE_EXTENSIONS.has(ext) ? ext : '.jpg';
    return `${Date.now()}-${Math.round(Math.random() * 1e9)}${allowedExt}`;
  }

  avatarApiPath() {
    return '/api/v1/driver/profile/avatar';
  }

  vehiclePhotoApiPath() {
    return '/api/v1/driver/profile/vehicle-photo';
  }

  mapProfile(row) {
    const hasVehicle = Boolean(
      row.vehicle_id
      || row.plate_number
      || row.model_name
      || row.color
      || row.vehicle_type_code,
    );
    return {
      name: row.name,
      phone: row.phone,
      email: row.email,
      avatarUrl: row.avatar_url || (row.avatar_file_id ? this.avatarApiPath() : null),
      vehicle: hasVehicle
        ? {
            typeCode: row.vehicle_type_code ?? null,
            typeName: row.vehicle_type_name ?? null,
            modelName: row.model_name ?? null,
            plateNumber: row.plate_number ?? null,
            color: row.color ?? null,
            year: row.vehicle_year == null ? null : Number(row.vehicle_year),
            photoUrl: row.vehicle_photo_file_id ? this.vehiclePhotoApiPath() : null,
          }
        : null,
    };
  }

  async getProfile(driverUserId) {
    const row = await this.driverRepository.findProfileByUserId(driverUserId);
    if (!row || !row.is_active) {
      this.notFound();
    }
    const avatarFile = await this.driverRepository.findAvatarFileByUserId(driverUserId);
    if (avatarFile) {
      row.avatar_file_id = avatarFile.id;
      row.avatar_url = this.avatarApiPath();
    }
    return this.mapProfile(row);
  }

  async updateProfile(driverUserId, input) {
    const allowed = {};
    if (input.name !== undefined) allowed.name = this.normalizeName(input.name);
    if (input.phone !== undefined) allowed.phone = this.normalizePhone(input.phone);

    let vehicleTypeId = null;
    if (input.vehicleTypeCode !== undefined) {
      const code = String(input.vehicleTypeCode).trim().toUpperCase();
      const vehicleType = await this.vehicleRepository.findTypeByCode(code);
      if (!vehicleType) {
        this.validation('Invalid vehicle type', 'vehicleTypeCode');
      }
      vehicleTypeId = vehicleType.id;
      allowed.vehicleTypeCode = code;
    }

    const vehicleFields = {};
    if (input.vehicleModelName !== undefined) {
      vehicleFields.modelName = String(input.vehicleModelName).trim() || null;
    }
    if (input.vehiclePlateNumber !== undefined) {
      const plate = String(input.vehiclePlateNumber).trim().replace(/\s+/gu, ' ');
      if (!plate) {
        this.validation('Plate number is required', 'vehiclePlateNumber');
      }
      vehicleFields.plateNumber = plate;
    }
    if (input.vehicleColor !== undefined) {
      vehicleFields.color = String(input.vehicleColor).trim() || null;
    }
    if (input.vehicleYear !== undefined) {
      vehicleFields.vehicleYear = this.normalizeVehicleYear(input.vehicleYear);
    }

    if (
      Object.keys(allowed).length === 0
      && Object.keys(vehicleFields).length === 0
      && vehicleTypeId == null
    ) {
      this.validation('No updatable fields provided');
    }

    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      const row = await this.driverRepository.findProfileByUserIdForUpdate(conn, driverUserId);
      if (!row) {
        this.notFound();
      }

      if (allowed.name || allowed.phone) {
        await this.driverRepository.updateSelfProfile(conn, {
          driverId: row.id,
          userId: row.user_id,
          name: allowed.name ?? row.name,
          phone: allowed.phone ?? row.phone,
          actorUserId: driverUserId,
        });
      }

      const nextVehicleTypeId = vehicleTypeId ?? row.vehicle_type_id;
      const hasVehiclePatch = nextVehicleTypeId
        && (
          vehicleTypeId != null
          || vehicleFields.plateNumber != null
          || vehicleFields.modelName != null
          || vehicleFields.color != null
        );

      if (hasVehiclePatch) {
        const plateNumber = vehicleFields.plateNumber ?? row.plate_number;
        const modelName = vehicleFields.modelName ?? row.model_name;
        const color = vehicleFields.color ?? row.color;
        if (!plateNumber) {
          this.validation('Plate number is required', 'vehiclePlateNumber');
        }
        if (row.vehicle_id) {
          await this.driverRepository.updatePrimaryVehicle(conn, {
            vehicleId: row.vehicle_id,
            driverId: row.id,
            vehicleTypeId: nextVehicleTypeId,
            plateNumber,
            modelName,
            color,
            actorUserId: driverUserId,
          });
        } else {
          await this.driverRepository.insertPrimaryVehicle(conn, {
            driverId: row.id,
            vehicleTypeId: nextVehicleTypeId,
            plateNumber,
            modelName,
            color,
            actorUserId: driverUserId,
          });
        }
      }

      if (vehicleFields.vehicleYear != null && row.application_id) {
        await this.driverRepository.updateApplicationVehicleYear(
          conn,
          row.application_id,
          vehicleFields.vehicleYear,
        );
      }

      await conn.commit();
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }

    return this.getProfile(driverUserId);
  }

  async uploadAvatar(driverUserId, file) {
    this.validateImageFile(file, 'avatar');
    const row = await this.driverRepository.findProfileByUserId(driverUserId);
    if (!row) this.notFound();

    const conn = await this.pool.getConnection();
    let stagedPath = null;
    try {
      await conn.beginTransaction();
      const previous = await this.driverRepository.findAvatarFileByUserId(driverUserId);
      const storedName = this.safeStoredFilename(file, 'avatar');
      const destDir = path.join(uploadDir, 'drivers', String(driverUserId), 'avatar');
      fs.mkdirSync(destDir, { recursive: true });
      stagedPath = path.join(destDir, storedName);
      fs.copyFileSync(file.path, stagedPath);
      const relativePath = path.join('drivers', String(driverUserId), 'avatar', storedName);

      const fileId = await this.fileRepository.insert(conn, {
        entityType: 'DRIVER_AVATAR',
        entityId: driverUserId,
        filePath: relativePath,
        mimeType: file.mimetype,
        fileSize: file.size,
        originalFilename: path.basename(file.originalname || 'avatar').replace(/[^\w.\-]/g, '_'),
        uploadedByUserId: driverUserId,
        createdBy: driverUserId,
        updatedBy: driverUserId,
      });

      await this.driverRepository.updateAvatarUrl(conn, driverUserId, this.avatarApiPath());

      if (previous?.id) {
        await this.fileRepository.softDelete(conn, previous.id);
      }

      await conn.commit();
      return { avatarUrl: this.avatarApiPath(), fileId };
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
      if (stagedPath && fs.existsSync(file.path)) {
        try {
          fs.unlinkSync(file.path);
        } catch (_) {
          // ignore temp cleanup errors
        }
      }
    }
  }

  async uploadVehiclePhoto(driverUserId, file) {
    this.validateImageFile(file, 'vehiclePhoto');
    const row = await this.driverRepository.findProfileByUserId(driverUserId);
    if (!row?.application_id) {
      throw new AppError('Vehicle photo cannot be updated for this account', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }

    const conn = await this.pool.getConnection();
    let stagedPath = null;
    try {
      await conn.beginTransaction();
      const previous = await this.driverRepository.findVehiclePhotoFileByDriverId(row.driver_id);
      const storedName = this.safeStoredFilename(file, 'vehicle');
      const destDir = path.join(uploadDir, 'drivers', String(driverUserId), 'vehicle');
      fs.mkdirSync(destDir, { recursive: true });
      stagedPath = path.join(destDir, storedName);
      fs.copyFileSync(file.path, stagedPath);
      const relativePath = path.join('drivers', String(driverUserId), 'vehicle', storedName);

      const fileId = await this.fileRepository.insert(conn, {
        entityType: 'DRIVER_VEHICLE_PHOTO',
        entityId: row.driver_id,
        filePath: relativePath,
        mimeType: file.mimetype,
        fileSize: file.size,
        originalFilename: path.basename(file.originalname || 'vehicle').replace(/[^\w.\-]/g, '_'),
        uploadedByUserId: driverUserId,
        createdBy: driverUserId,
        updatedBy: driverUserId,
      });

      if (this.driverApplicationRepository) {
        await this.driverApplicationRepository.insertApplicationFile(conn, {
          applicationId: row.application_id,
          fileId,
          category: 'DRIVER_VEHICLE_PHOTO',
          sortOrder: 0,
        });
      }

      if (previous?.id) {
        await this.fileRepository.softDelete(conn, previous.id);
      }

      await conn.commit();
      return { vehiclePhotoUrl: this.vehiclePhotoApiPath(), fileId };
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
      if (stagedPath && fs.existsSync(file.path)) {
        try {
          fs.unlinkSync(file.path);
        } catch (_) {
          // ignore temp cleanup errors
        }
      }
    }
  }

  async streamAvatar(driverUserId) {
    const file = await this.driverRepository.findAvatarFileByUserId(driverUserId);
    if (!file) {
      throw new AppError('File not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.FILE_NOT_FOUND,
      });
    }
    return file;
  }

  async streamVehiclePhoto(driverUserId) {
    const row = await this.driverRepository.findProfileByUserId(driverUserId);
    if (!row) this.notFound();
    const file = await this.driverRepository.findVehiclePhotoFileByDriverId(row.driver_id);
    if (!file) {
      throw new AppError('File not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.FILE_NOT_FOUND,
      });
    }
    return file;
  }

}

module.exports = DriverProfileService;

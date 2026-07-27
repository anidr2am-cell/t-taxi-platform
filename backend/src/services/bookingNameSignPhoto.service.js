const path = require('path');
const fs = require('fs');
const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const { uploadDir } = require('../config/multer');

const IMAGE_EXTENSIONS = new Set(['.jpg', '.jpeg', '.png', '.webp']);
const IMAGE_MIME_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);
const GENERIC_MIME_TYPES = new Set(['', 'application/octet-stream']);

class BookingNameSignPhotoService {
  constructor(pool, bookingRepository, fileRepository) {
    this.pool = pool;
    this.bookingRepository = bookingRepository;
    this.fileRepository = fileRepository;
  }

  validateBookingNumber(bookingNumber) {
    const value = String(bookingNumber ?? '').trim().toUpperCase();
    if (!/^TX\d{12}$/.test(value)) {
      throw new AppError('Invalid booking number', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }
    return value;
  }

  validateImageFile(file) {
    if (!file) {
      throw new AppError('Image file is required', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
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

  safeStoredFilename(file) {
    const ext = path.extname(file.originalname || '').toLowerCase().replace(/[^a-z0-9.]/g, '');
    const allowedExt = IMAGE_EXTENSIONS.has(ext) ? ext : '.jpg';
    return `${Date.now()}-${Math.round(Math.random() * 1e9)}${allowedExt}`;
  }

  apiPath(bookingNumber) {
    return `/api/v1/driver/bookings/${bookingNumber}/name-sign-photo`;
  }

  resolveAbsolutePath(relativePath) {
    const normalized = path.normalize(relativePath).replace(/^(\.\.(\/|\\|$))+/, '');
    const absolute = path.join(uploadDir, normalized);
    if (!absolute.startsWith(uploadDir)) {
      throw new AppError('Invalid file path', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.FILE_NOT_FOUND,
      });
    }
    return absolute;
  }

  sanitizeFilename(name) {
    return String(name || 'name-sign-photo').replace(/[^\w.\-]/g, '_').slice(0, 200)
      || 'name-sign-photo';
  }

  async upload(driverUserId, bookingNumber, file) {
    const normalizedBookingNumber = this.validateBookingNumber(bookingNumber);
    this.validateImageFile(file);

    const conn = await this.pool.getConnection();
    let stagedFinalPath = null;
    try {
      await conn.beginTransaction();
      const booking = await this.bookingRepository.findActiveDriverBookingByNumberForUpdate(
        conn,
        driverUserId,
        normalizedBookingNumber,
      );
      if (!booking) {
        const exists = await this.bookingRepository.findByBookingNumberForUpdate(
          conn,
          normalizedBookingNumber,
        );
        throw new AppError(exists ? 'Booking is not assigned to this driver' : 'Booking not found', {
          statusCode: exists ? HTTP_STATUS.FORBIDDEN : HTTP_STATUS.NOT_FOUND,
          errorCode: exists ? ERROR_CODES.FORBIDDEN : ERROR_CODES.BOOKING_NOT_FOUND,
        });
      }

      const previousFileId = booking.name_sign_photo_file_id;
      const storedName = this.safeStoredFilename(file);
      const destDir = path.join(uploadDir, 'bookings', normalizedBookingNumber, 'name-sign');
      fs.mkdirSync(destDir, { recursive: true });
      stagedFinalPath = path.join(destDir, storedName);
      fs.copyFileSync(file.path, stagedFinalPath);
      const relativePath = path.join('bookings', normalizedBookingNumber, 'name-sign', storedName);

      const fileId = await this.fileRepository.insert(conn, {
        entityType: 'BOOKING_NAME_SIGN_PHOTO',
        entityId: booking.id,
        filePath: relativePath,
        mimeType: file.mimetype,
        fileSize: file.size,
        originalFilename: path.basename(file.originalname || 'name-sign-photo').replace(/[^\w.\-]/g, '_'),
        uploadedByUserId: driverUserId,
        createdBy: driverUserId,
        updatedBy: driverUserId,
      });

      await this.bookingRepository.updateNameSignPhotoFile(conn, booking.id, fileId, driverUserId);
      if (previousFileId) {
        await this.fileRepository.softDelete(conn, previousFileId);
      }
      await conn.commit();
      return {
        bookingNumber: normalizedBookingNumber,
        nameSignPhotoFileId: fileId,
        nameSignPhotoUrl: this.apiPath(normalizedBookingNumber),
      };
    } catch (err) {
      await conn.rollback();
      if (stagedFinalPath && fs.existsSync(stagedFinalPath)) {
        fs.rmSync(stagedFinalPath, { force: true });
      }
      throw err;
    } finally {
      conn.release();
      if (file?.path && fs.existsSync(file.path)) {
        fs.rmSync(file.path, { force: true });
      }
    }
  }

  async getDriverFile(driverUserId, bookingNumber) {
    const normalizedBookingNumber = this.validateBookingNumber(bookingNumber);
    const file = await this.bookingRepository.findNameSignPhotoFileForDriver(
      driverUserId,
      normalizedBookingNumber,
    );
    if (!file) {
      throw new AppError('File not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.FILE_NOT_FOUND,
      });
    }
    const absolutePath = this.resolveAbsolutePath(file.file_path);
    if (!fs.existsSync(absolutePath)) {
      throw new AppError('File not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.FILE_NOT_FOUND,
      });
    }
    return {
      absolutePath,
      mimeType: file.mime_type || 'application/octet-stream',
      fileName: this.sanitizeFilename(file.original_filename || 'name-sign-photo'),
    };
  }
}

module.exports = BookingNameSignPhotoService;

const path = require('path');
const fs = require('fs');
const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const COMMISSION_STATUS = require('../constants/commissionStatus');
const ROLES = require('../constants/roles');
const { uploadDir } = require('../config/multer');
const logger = require('../utils/logger');
const { randomUUID } = require('node:crypto');
const { EVENTS } = require('../events');

const ADMIN_RECONCILE_BATCH_LIMIT = 100;

function settlementApiBase(segment) {
  const config = require('../config');
  return `/api/${config.server.apiVersion}/${segment}`;
}

const ALLOWED_MIME = new Set([
  'image/jpeg',
  'image/png',
  'application/pdf',
]);

const ALLOWED_EXT = new Set(['.jpg', '.jpeg', '.png', '.pdf']);

const EXT_TO_MIME = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.pdf': 'application/pdf',
};

class CommissionSettlementService {
  constructor(
    pool,
    bookingRepository,
    driverRepository,
    fileRepository,
    settingsRepository,
    outboxRepository,
    outboxProcessor,
    bookingStatusService = null,
  ) {
    this.pool = pool;
    this.bookingRepository = bookingRepository;
    this.driverRepository = driverRepository;
    this.fileRepository = fileRepository;
    this.settingsRepository = settingsRepository;
    this.outboxRepository = outboxRepository;
    this.outboxProcessor = outboxProcessor;
    this.bookingStatusService = bookingStatusService;
  }

  parseMetadata(raw) {
    if (!raw) return {};
    if (typeof raw === 'object') return { ...raw };
    try {
      return JSON.parse(raw) ?? {};
    } catch {
      return {};
    }
  }

  formatDateTime(date) {
    return date.toISOString().slice(0, 19).replace('T', ' ');
  }

  addDays(date, days) {
    const result = new Date(date);
    result.setDate(result.getDate() + Number(days));
    return result;
  }

  async getCommissionConfig(conn) {
    const fixedRow = await this.settingsRepository.findByGroupAndKey(
      'settlement',
      'commission_fixed_amount',
      conn,
    );
    const dueDaysRow = await this.settingsRepository.findByGroupAndKey(
      'settlement',
      'commission_due_days',
      conn,
    );

    const fixedAmount = fixedRow?.value != null ? Number(fixedRow.value) : null;
    if (Number.isFinite(fixedAmount) && fixedAmount > 0) {
      const dueDays = dueDaysRow?.value ? Number(dueDaysRow.value) : null;
      if (dueDays != null && (!Number.isFinite(dueDays) || dueDays < 0)) {
        throw new AppError('Commission due days is not configured', {
          statusCode: HTTP_STATUS.INTERNAL_SERVER_ERROR,
          errorCode: ERROR_CODES.COMMISSION_NOT_CONFIGURED,
        });
      }
      return { fixedAmount, dueDays };
    }

    const rateRow = await this.settingsRepository.findByGroupAndKey(
      'settlement',
      'commission_rate_percent',
      conn,
    );

    if (!rateRow?.value) {
      throw new AppError('Commission rate is not configured', {
        statusCode: HTTP_STATUS.INTERNAL_SERVER_ERROR,
        errorCode: ERROR_CODES.COMMISSION_NOT_CONFIGURED,
      });
    }

    const ratePercent = Number(rateRow.value);
    if (!Number.isFinite(ratePercent) || ratePercent <= 0 || ratePercent > 100) {
      throw new AppError('Commission rate is not configured', {
        statusCode: HTTP_STATUS.INTERNAL_SERVER_ERROR,
        errorCode: ERROR_CODES.COMMISSION_NOT_CONFIGURED,
      });
    }

    const dueDays = dueDaysRow?.value ? Number(dueDaysRow.value) : null;
    if (dueDays != null && (!Number.isFinite(dueDays) || dueDays < 0)) {
      throw new AppError('Commission due days is not configured', {
        statusCode: HTTP_STATUS.INTERNAL_SERVER_ERROR,
        errorCode: ERROR_CODES.COMMISSION_NOT_CONFIGURED,
      });
    }
    return { ratePercent, dueDays };
  }

  isOverdue(row, now = new Date()) {
    if (
      row.commission_status === COMMISSION_STATUS.PAID
      || row.commission_status === COMMISSION_STATUS.WAIVED
      || row.commission_status === COMMISSION_STATUS.NOT_DUE_YET
    ) {
      return false;
    }
    if (!row.commission_due_at) return false;
    return new Date(row.commission_due_at).getTime() < now.getTime();
  }

  isSettlementBlocking(row, metadata, now = new Date()) {
    if (
      row.commission_status === COMMISSION_STATUS.PAID
      || row.commission_status === COMMISSION_STATUS.WAIVED
      || row.commission_status === COMMISSION_STATUS.NOT_DUE_YET
    ) {
      return false;
    }
    return true;
  }

  hasCommissionReceipt(row) {
    if (row.commission_receipt_file_id == null) return false;
    // Require joined files row; orphaned file id must not count as submitted.
    return row.receipt_mime_type != null
      || row.receipt_original_filename != null
      || row.receipt_file_size != null;
  }

  isReceiptRejected(row, metadata) {
    return Boolean(
      metadata.commissionRejectionReason
      && !this.hasCommissionReceipt(row),
    );
  }

  mapPublicCommissionStatus(row, metadata, now = new Date()) {
    if (row.commission_status === COMMISSION_STATUS.PAID) return 'APPROVED';
    if (this.isReceiptRejected(row, metadata)) return 'REJECTED';
    if (this.hasCommissionReceipt(row)) return 'RECEIPT_SUBMITTED';
    if (this.isOverdue(row, now)) return 'OVERDUE';
    return 'PENDING';
  }

  mapReceiptStatus(row, metadata) {
    if (row.commission_status === COMMISSION_STATUS.PAID) return 'APPROVED';
    if (this.isReceiptRejected(row, metadata)) return 'REJECTED';
    if (this.hasCommissionReceipt(row)) return 'RECEIPT_SUBMITTED';
    return 'NONE';
  }

  computeCanApprove(row, metadata) {
    if (row.status !== 'SETTLEMENT_PENDING') return false;
    if (row.commission_status === COMMISSION_STATUS.PAID) return false;
    if (this.isReceiptRejected(row, metadata)) return false;
    return this.hasCommissionReceipt(row);
  }

  mapSettlementListItem(row, apiBasePath, role) {
    const metadata = this.parseMetadata(row.metadata);
    const commissionStatus = this.mapPublicCommissionStatus(row, metadata);
    const receiptStatus = this.mapReceiptStatus(row, metadata);
    const item = {
      bookingNumber: row.booking_number,
      status: row.status,
      pickupDate: row.pickup_date ?? null,
      pickupTime: row.pickup_time ?? null,
      origin: row.origin_address ?? null,
      destination: row.destination_address ?? null,
      completedAt: row.completed_at,
      commissionAmount: row.commission_amount != null ? Number(row.commission_amount) : null,
      currency: row.currency,
      commissionStatus,
      dueAt: row.commission_due_at,
      receiptStatus,
      receiptSubmittedAt: row.receipt_uploaded_at ?? metadata.commissionReceiptSubmittedAt ?? null,
      receiptUploadedAt: row.receipt_uploaded_at ?? metadata.commissionReceiptSubmittedAt ?? null,
      rejectionReason: metadata.commissionRejectionReason ?? null,
    };
    if (this.hasCommissionReceipt(row)) {
      item.receiptFileId = Number(row.commission_receipt_file_id);
    }
    if (role === ROLES.ADMIN || role === ROLES.SUPER_ADMIN) {
      item.driverId = row.driver_id;
      item.driverName = row.driver_name;
      item.driverPhone = row.driver_phone;
      item.canApprove = this.computeCanApprove(row, metadata);
    }
    if (this.hasCommissionReceipt(row) && apiBasePath) {
      item.receiptUrl = `${apiBasePath}/${row.booking_number}/receipt`;
    }
    return item;
  }

  mapAdminDetail(row, apiBasePath) {
    const metadata = this.parseMetadata(row.metadata);
    const listItem = this.mapSettlementListItem(row, apiBasePath, ROLES.ADMIN);
    return {
      ...listItem,
      canApprove: this.computeCanApprove(row, metadata),
      bookingSummary: {
        bookingNumber: row.booking_number,
        completedAt: row.completed_at,
        totalAmount: Number(row.total_amount),
        currency: row.currency,
      },
      driverSummary: {
        driverId: row.driver_id,
        displayName: row.driver_name,
        phone: row.driver_phone,
      },
      commissionPaidAt: row.commission_paid_at,
      receiptMetadata: this.hasCommissionReceipt(row)
        ? {
            mimeType: row.receipt_mime_type,
            fileSize: row.receipt_file_size,
            originalFilename: row.receipt_original_filename,
            uploadedAt: row.receipt_uploaded_at ?? metadata.commissionReceiptSubmittedAt,
          }
        : null,
      reviewHistory: metadata.commissionReviewHistory ?? [],
    };
  }

  async reconcileMissingObligationsForAdminList(filters) {
    const bookingIds = await this.bookingRepository.findCompletedBookingIdsMissingObligationForAdmin(
      filters,
      ADMIN_RECONCILE_BATCH_LIMIT,
    );
    for (const bookingId of bookingIds) {
      try {
        await this.activateObligationForCompletedBooking(bookingId);
      } catch (err) {
        logger.warn('Commission obligation reconciliation failed', {
          bookingId,
          error: err.message,
        });
      }
    }
  }

  async reconcileMissingObligationsForDriver(driverId) {
    const bookingIds = await this.bookingRepository.findCompletedBookingIdsMissingObligation(
      driverId,
    );
    for (const bookingId of bookingIds) {
      await this.activateObligationForCompletedBooking(bookingId);
    }
  }

  async reconcileMissingObligationForBooking(bookingNumber) {
    const row = await this.bookingRepository.findSettlementByBookingNumber(bookingNumber);
    if (!row || row.status !== 'COMPLETED') return;
    if (
      row.commission_status !== COMMISSION_STATUS.NOT_DUE_YET
      && row.commission_status !== COMMISSION_STATUS.PENDING_AFTER_COMPLETION
      && row.commission_amount != null
    ) {
      return;
    }
    await this.activateObligationForCompletedBooking(row.id);
  }

  async activateObligationForCompletedBooking(bookingId) {
    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      const [rows] = await conn.query(
        `
        SELECT id, booking_number, status, total_amount, currency,
               commission_status, commission_amount, completed_at, driver_id
          FROM bookings
          WHERE id = ? AND deleted_at IS NULL
          FOR UPDATE
        `,
        [bookingId],
      );
      const booking = rows[0];
      if (!booking || booking.status !== 'COMPLETED') {
        await conn.commit();
        return;
      }

      if (
        booking.commission_status !== COMMISSION_STATUS.NOT_DUE_YET
        && booking.commission_status !== COMMISSION_STATUS.PENDING_AFTER_COMPLETION
        && booking.commission_amount != null
      ) {
        await conn.commit();
        return;
      }

      const { ratePercent, fixedAmount, dueDays } = await this.getCommissionConfig(conn);
      const amount = fixedAmount != null
        ? Math.round(Number(fixedAmount) * 100) / 100
        : Math.round(Number(booking.total_amount) * ratePercent / 100 * 100) / 100;
      const completedAt = booking.completed_at ? new Date(booking.completed_at) : new Date();
      const dueAt = dueDays != null && Number.isFinite(dueDays)
        ? this.formatDateTime(this.addDays(completedAt, dueDays))
        : null;

      await this.bookingRepository.updateCommissionFields(conn, booking.id, {
        commissionStatus: COMMISSION_STATUS.DUE,
        commissionAmount: amount,
        commissionDueAt: dueAt,
      });

      await this.bookingRepository.insertActivityLog(conn, booking.id, {
        activityType: 'COMMISSION_OBLIGATION_CREATED',
        actorUserId: null,
        actorRole: 'SYSTEM',
        description: `Commission obligation created for ${booking.booking_number}`,
        payload: {
          bookingNumber: booking.booking_number,
          commissionAmount: amount,
          commissionDueAt: dueAt,
        },
      });

      let outboxId = null;
      if (booking.driver_id && this.outboxRepository) {
        const driver = await this.driverRepository.findByIdForUpdate(conn, booking.driver_id);
        if (driver?.user_id) {
          outboxId = await this.outboxRepository.insertNotificationEvent(conn, {
            aggregateId: booking.id,
            eventType: EVENTS.COMMISSION_REQUIRED,
            payload: {
              eventId: randomUUID(),
              eventName: EVENTS.COMMISSION_REQUIRED,
              bookingId: booking.id,
              bookingNumber: booking.booking_number,
              driverUserId: driver.user_id,
              driverId: driver.id,
            },
          });
        }
      }

      await conn.commit();

      if (outboxId && this.outboxProcessor) {
        await this.outboxProcessor.dispatchOutboxIds([outboxId]);
      }
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }

  async resolveDriver(driverUserId) {
    const driver = await this.driverRepository.findByUserId(driverUserId);
    if (!driver) {
      throw new AppError('Driver not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.DRIVER_NOT_FOUND,
      });
    }
    return driver;
  }

  async listDriverSettlements(driverUserId, apiBasePath) {
    const driver = await this.resolveDriver(driverUserId);
    await this.reconcileMissingObligationsForDriver(driver.id);
    const rows = await this.bookingRepository.findDriverSettlements(driver.id);
    return rows.map((row) => this.mapSettlementListItem(row, apiBasePath, ROLES.DRIVER));
  }

  async getDriverSettlement(driverUserId, bookingNumber, apiBasePath) {
    const driver = await this.resolveDriver(driverUserId);
    const owns = await this.bookingRepository.driverOwnsSettlementBooking(
      driver.id,
      bookingNumber,
    );
    if (!owns) {
      throw new AppError('Settlement not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.SETTLEMENT_NOT_FOUND,
      });
    }
    await this.reconcileMissingObligationForBooking(bookingNumber);
    const row = await this.bookingRepository.findSettlementByBookingNumber(bookingNumber);
    if (!row || !['SETTLEMENT_PENDING', 'COMPLETED'].includes(row.status)
      || row.commission_status === COMMISSION_STATUS.NOT_DUE_YET
      || row.commission_status === COMMISSION_STATUS.WAIVED) {
      throw new AppError('Settlement not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.SETTLEMENT_NOT_FOUND,
      });
    }
    const item = this.mapSettlementListItem(row, apiBasePath, ROLES.DRIVER);
    const settings = this.settingsRepository?.findByGroup
      ? await this.settingsRepository.findByGroup('operations')
      : [];
    const values = Object.fromEntries(settings.map((entry) => [entry.key_name, entry.value]));
    return {
      ...item,
      paymentInstructions: {
        bankName: values.bankName || '',
        accountName: values.accountName || '',
        accountNumber: values.accountNumber || '',
        promptPayNumber: values.promptPayNumber || '',
        promptPayQrImageUrl: values.promptPayQrImagePath
          ? '/api/v1/settings/assets/promptPayQr'
          : null,
      },
    };
  }

  validateUploadedFile(file) {
    if (!file) {
      throw new AppError('Receipt file is required', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }
    const ext = path.extname(file.originalname || '').toLowerCase();
    if (!ext || !ALLOWED_EXT.has(ext)) {
      throw new AppError('Invalid file type', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.INVALID_FILE_TYPE,
      });
    }
    if (!ALLOWED_MIME.has(file.mimetype)) {
      throw new AppError('Invalid file type', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.INVALID_FILE_TYPE,
      });
    }
    const expectedMime = EXT_TO_MIME[ext];
    if (expectedMime && file.mimetype !== expectedMime) {
      throw new AppError('File extension does not match content type', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.INVALID_FILE_TYPE,
      });
    }
  }

  safeStoredFilename(file) {
    const ext = path.extname(file.originalname || '').toLowerCase().replace(/[^a-z0-9.]/g, '');
    const allowedExt = ALLOWED_EXT.has(ext) ? ext : '.bin';
    return `${Date.now()}-${Math.round(Math.random() * 1e9)}${allowedExt}`;
  }

  async uploadReceipt(driverUserId, bookingNumber, file) {
    this.validateUploadedFile(file);
    const driver = await this.resolveDriver(driverUserId);
    const conn = await this.pool.getConnection();
    let stagedFinalPath = null;
    let transactionCommitted = false;

    try {
      await conn.beginTransaction();
      const row = await this.bookingRepository.findSettlementByBookingNumberForUpdate(
        conn,
        bookingNumber,
      );
      if (!row || !['SETTLEMENT_PENDING', 'COMPLETED'].includes(row.status)) {
        throw new AppError('Settlement not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.SETTLEMENT_NOT_FOUND,
        });
      }

      const owns = await this.bookingRepository.driverOwnsSettlementBooking(
        driver.id,
        bookingNumber,
      );
      if (!owns) {
        throw new AppError('Settlement not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.SETTLEMENT_NOT_FOUND,
        });
      }

      if (row.commission_status === COMMISSION_STATUS.PAID) {
        throw new AppError('Receipt cannot be changed after approval', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.RECEIPT_ALREADY_APPROVED,
        });
      }

      const metadata = this.parseMetadata(row.metadata);
      const previousFileId = row.commission_receipt_file_id;
      const storedName = this.safeStoredFilename(file);
      const destDir = path.join(uploadDir, 'settlements', bookingNumber);
      fs.mkdirSync(destDir, { recursive: true });
      stagedFinalPath = path.join(destDir, storedName);
      fs.copyFileSync(file.path, stagedFinalPath);
      const relativePath = path.join('settlements', bookingNumber, storedName);

      const fileId = await this.fileRepository.insert(conn, {
        entityType: 'COMMISSION_RECEIPT',
        entityId: row.id,
        filePath: relativePath,
        mimeType: file.mimetype,
        fileSize: file.size,
        originalFilename: path.basename(file.originalname || 'receipt').replace(/[^\w.\-]/g, '_'),
        uploadedByUserId: driverUserId,
        createdBy: driverUserId,
        updatedBy: driverUserId,
      });

      metadata.commissionReceiptSubmittedAt = new Date().toISOString();
      delete metadata.commissionRejectionReason;

      await this.bookingRepository.updateCommissionFields(conn, row.id, {
        commissionReceiptFileId: fileId,
        metadata,
        updatedBy: driverUserId,
      });

      if (previousFileId) {
        await this.fileRepository.softDelete(conn, previousFileId);
      }

      await this.bookingRepository.insertActivityLog(conn, row.id, {
        activityType: 'COMMISSION_RECEIPT_UPLOADED',
        actorUserId: driverUserId,
        actorRole: ROLES.DRIVER,
        description: `Commission receipt uploaded for ${bookingNumber}`,
        payload: { bookingNumber, fileId },
      });

      let outboxId = null;
      if (this.outboxRepository) {
        outboxId = await this.outboxRepository.insertNotificationEvent(conn, {
          aggregateId: row.id,
          eventType: EVENTS.RECEIPT_SUBMITTED,
          payload: {
            eventId: randomUUID(),
            eventName: EVENTS.RECEIPT_SUBMITTED,
            bookingId: row.id,
            bookingNumber,
          },
        });
      }

      await conn.commit();
      transactionCommitted = true;

      if (outboxId && this.outboxProcessor) {
        await this.outboxProcessor.dispatchOutboxIds([outboxId]);
      }

      if (file?.path && fs.existsSync(file.path)) {
        try {
          fs.unlinkSync(file.path);
        } catch (cleanupError) {
          logger.warn('Receipt temporary file cleanup failed', {
            error: cleanupError.message,
          });
        }
      }

      const updated = await this.bookingRepository.findSettlementByBookingNumber(bookingNumber);
      const mapped = this.mapSettlementListItem(
        updated,
        settlementApiBase('driver/settlements'),
        ROLES.DRIVER,
      );
      if (!this.hasCommissionReceipt(updated)) {
        throw new AppError('Receipt was not saved', {
          statusCode: HTTP_STATUS.INTERNAL_SERVER_ERROR,
          errorCode: ERROR_CODES.INTERNAL_SERVER_ERROR,
        });
      }
      if (mapped.receiptStatus !== 'RECEIPT_SUBMITTED') {
        throw new AppError('Receipt was not saved', {
          statusCode: HTTP_STATUS.INTERNAL_SERVER_ERROR,
          errorCode: ERROR_CODES.INTERNAL_SERVER_ERROR,
        });
      }
      return mapped;
    } catch (err) {
      if (!transactionCommitted) {
        try {
          await conn.rollback();
        } catch (rollbackError) {
          logger.warn('Receipt transaction rollback failed', {
            error: rollbackError.message,
          });
        }

        if (stagedFinalPath && fs.existsSync(stagedFinalPath)) {
          try {
            fs.unlinkSync(stagedFinalPath);
          } catch (cleanupError) {
            logger.warn('Uncommitted receipt file cleanup failed', {
              error: cleanupError.message,
            });
          }
        }
      }
      if (file?.path && fs.existsSync(file.path)) {
        try {
          fs.unlinkSync(file.path);
        } catch (cleanupError) {
          logger.warn('Receipt temporary file cleanup failed', {
            error: cleanupError.message,
          });
        }
      }
      throw err;
    } finally {
      conn.release();
    }
  }

  parseAdminFilters(query) {
    const filters = {
      status: query.status || null,
      driverId: query.driverId ? Number(query.driverId) : null,
      bookingNumber: query.bookingNumber?.trim() || null,
      overdueOnly: query.overdueOnly === 'true' || query.overdueOnly === true,
      completedDateFrom: null,
      completedDateTo: null,
    };
    if (query.completedDateFrom) {
      filters.completedDateFrom = `${query.completedDateFrom} 00:00:00`;
    }
    if (query.completedDateTo) {
      const end = new Date(`${query.completedDateTo}T00:00:00`);
      end.setDate(end.getDate() + 1);
      filters.completedDateTo = end.toISOString().slice(0, 19).replace('T', ' ');
    }
    return filters;
  }

  parsePagination(query) {
    const page = Number(query.page) || 1;
    const limit = Number(query.limit ?? query.page_size) || 20;
    const safeLimit = Math.min(Math.max(limit, 1), 100);
    const offset = (Math.max(page, 1) - 1) * safeLimit;
    return { page: Math.max(page, 1), limit: safeLimit, offset };
  }

  async listAdminSettlements(query, apiBasePath) {
    const filters = this.parseAdminFilters(query);
    const pagination = this.parsePagination(query);
    await this.reconcileMissingObligationsForAdminList(filters);
    const total = await this.bookingRepository.countAdminSettlements(filters);
    const rows = await this.bookingRepository.findAdminSettlements(filters, pagination);
    return {
      page: pagination.page,
      pageSize: pagination.limit,
      total,
      items: rows.map((row) => this.mapSettlementListItem(row, apiBasePath, ROLES.ADMIN)),
    };
  }

  async getAdminSettlement(bookingNumber, apiBasePath) {
    await this.reconcileMissingObligationForBooking(bookingNumber);
    const row = await this.bookingRepository.findSettlementByBookingNumber(bookingNumber);
    if (!row || !['SETTLEMENT_PENDING', 'COMPLETED'].includes(row.status)
      || row.commission_status === COMMISSION_STATUS.NOT_DUE_YET
      || row.commission_status === COMMISSION_STATUS.WAIVED) {
      throw new AppError('Settlement not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.SETTLEMENT_NOT_FOUND,
      });
    }
    return this.mapAdminDetail(row, apiBasePath);
  }

  async approve(bookingNumber, user) {
    const conn = await this.pool.getConnection();
    let bookingTransition = null;
    try {
      await conn.beginTransaction();
      const row = await this.bookingRepository.findSettlementByBookingNumberForUpdate(
        conn,
        bookingNumber,
      );
      if (!row) {
        throw new AppError('Settlement not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.SETTLEMENT_NOT_FOUND,
        });
      }

      if (row.status === 'COMPLETED' && row.commission_status === COMMISSION_STATUS.PAID) {
        await conn.commit();
        const current = await this.bookingRepository.findSettlementByBookingNumber(bookingNumber);
        return this.mapAdminDetail(current, null);
      }

      if (row.status !== 'SETTLEMENT_PENDING') {
        throw new AppError('Settlement is not awaiting confirmation', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.INVALID_STATUS_TRANSITION,
        });
      }

      if (!row.commission_receipt_file_id) {
        throw new AppError('Receipt must be submitted before approval', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.RECEIPT_REQUIRED,
        });
      }

      const metadata = this.parseMetadata(row.metadata);
      const reviewEntry = {
        action: 'APPROVED',
        reviewedByUserId: user.id,
        reviewedAt: new Date().toISOString(),
      };
      metadata.commissionReviewHistory = [...(metadata.commissionReviewHistory ?? []), reviewEntry];
      delete metadata.commissionRejectionReason;

      await this.bookingRepository.updateCommissionFields(conn, row.id, {
        commissionStatus: COMMISSION_STATUS.PAID,
        commissionPaidAt: this.formatDateTime(new Date()),
        metadata,
        updatedBy: user.id,
      });

      if (this.bookingStatusService) {
        bookingTransition = await this.bookingStatusService.transitionInTransaction(
          conn,
          bookingNumber,
          { status: 'COMPLETED', reason: 'SETTLEMENT_CONFIRMED' },
          user,
          { skipAccessCheck: true },
        );
      }

      await this.bookingRepository.insertActivityLog(conn, row.id, {
        activityType: 'COMMISSION_APPROVED',
        actorUserId: user.id,
        actorRole: user.role,
        description: `Commission approved for ${bookingNumber}`,
        payload: { bookingNumber },
      });

      let outboxId = null;
      if (this.outboxRepository) {
        const [driverRows] = await conn.query(
          `
            SELECT b.driver_id, d.user_id AS driver_user_id
            FROM bookings b
            INNER JOIN drivers d ON d.id = b.driver_id
            WHERE b.id = ? AND b.deleted_at IS NULL
            LIMIT 1
          `,
          [row.id],
        );
        const driverRow = driverRows[0];
        if (driverRow?.driver_user_id) {
          outboxId = await this.outboxRepository.insertNotificationEvent(conn, {
            aggregateId: row.id,
            eventType: EVENTS.SETTLEMENT_APPROVED,
            payload: {
              eventId: randomUUID(),
              eventName: EVENTS.SETTLEMENT_APPROVED,
              bookingId: row.id,
              bookingNumber,
              driverUserId: driverRow.driver_user_id,
              driverId: driverRow.driver_id,
            },
          });
        }
      }

      await conn.commit();

      if (outboxId && this.outboxProcessor) {
        await this.outboxProcessor.dispatchOutboxIds([outboxId]);
      }
      if (bookingTransition) {
        await this.bookingStatusService.dispatchOutboxAfterCommit(
          bookingTransition.outboxId,
        );
        this.bookingStatusService.emitDomainEvent(
          bookingTransition.domainEvent,
          bookingTransition.eventPayload,
        );
      }

      const updatedSettlement = await this.bookingRepository.findSettlementByBookingNumber(bookingNumber);

      return this.mapAdminDetail(updatedSettlement, null);
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }

  async reject(bookingNumber, reason, user) {
    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      const row = await this.bookingRepository.findSettlementByBookingNumberForUpdate(
        conn,
        bookingNumber,
      );
      if (!row || row.status !== 'SETTLEMENT_PENDING') {
        throw new AppError('Settlement not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.SETTLEMENT_NOT_FOUND,
        });
      }

      if (row.commission_status === COMMISSION_STATUS.PAID) {
        throw new AppError('Approved settlement cannot be rejected', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.RECEIPT_ALREADY_APPROVED,
        });
      }

      const metadata = this.parseMetadata(row.metadata);
      if (
        metadata.commissionRejectionReason === reason
        && !row.commission_receipt_file_id
        && row.commission_status !== COMMISSION_STATUS.PAID
      ) {
        await conn.commit();
        const current = await this.bookingRepository.findSettlementByBookingNumber(bookingNumber);
        return this.mapAdminDetail(current, null);
      }

      if (!row.commission_receipt_file_id) {
        throw new AppError('Receipt must be submitted before rejection', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.RECEIPT_REQUIRED,
        });
      }

      if (row.commission_receipt_file_id) {
        await this.fileRepository.softDelete(conn, row.commission_receipt_file_id);
      }

      metadata.commissionRejectionReason = reason;
      metadata.commissionReviewHistory = [
        ...(metadata.commissionReviewHistory ?? []),
        {
          action: 'REJECTED',
          reason,
          reviewedByUserId: user.id,
          reviewedAt: new Date().toISOString(),
        },
      ];

      await this.bookingRepository.updateCommissionFields(conn, row.id, {
        commissionReceiptFileId: null,
        metadata,
        updatedBy: user.id,
      });

      await this.bookingRepository.insertActivityLog(conn, row.id, {
        activityType: 'COMMISSION_REJECTED',
        actorUserId: user.id,
        actorRole: user.role,
        description: `Commission receipt rejected for ${bookingNumber}`,
        payload: { bookingNumber, reason },
      });

      let outboxId = null;
      if (this.outboxRepository) {
        const [driverRows] = await conn.query(
          `
            SELECT b.driver_id, d.user_id AS driver_user_id
            FROM bookings b
            INNER JOIN drivers d ON d.id = b.driver_id
            WHERE b.id = ? AND b.deleted_at IS NULL
            LIMIT 1
          `,
          [row.id],
        );
        const driverRow = driverRows[0];
        if (driverRow?.driver_user_id) {
          outboxId = await this.outboxRepository.insertNotificationEvent(conn, {
            aggregateId: row.id,
            eventType: EVENTS.RECEIPT_REJECTED,
            payload: {
              eventId: randomUUID(),
              eventName: EVENTS.RECEIPT_REJECTED,
              bookingId: row.id,
              bookingNumber,
              driverUserId: driverRow.driver_user_id,
              driverId: driverRow.driver_id,
            },
          });
        }
      }

      await conn.commit();

      if (outboxId && this.outboxProcessor) {
        await this.outboxProcessor.dispatchOutboxIds([outboxId]);
      }

      const updatedSettlement = await this.bookingRepository.findSettlementByBookingNumber(bookingNumber);

      return this.mapAdminDetail(updatedSettlement, null);
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }

  resolveReceiptAbsolutePath(relativePath) {
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

  sanitizeDownloadFilename(name) {
    const base = String(name || 'receipt').replace(/[^\w.\-]/g, '_');
    return base.slice(0, 200) || 'receipt';
  }

  async getReceiptFileForActor(actor, bookingNumber, role) {
    const row = await this.bookingRepository.findSettlementByBookingNumber(bookingNumber);
    if (!row || !row.commission_receipt_file_id) {
      throw new AppError('File not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.FILE_NOT_FOUND,
      });
    }

    if (role === ROLES.DRIVER) {
      const driver = await this.resolveDriver(actor.id);
      const owns = await this.bookingRepository.driverOwnsSettlementBooking(
        driver.id,
        bookingNumber,
      );
      if (!owns) {
        throw new AppError('File not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.FILE_NOT_FOUND,
        });
      }
    } else if (![ROLES.ADMIN, ROLES.SUPER_ADMIN].includes(role)) {
      throw new AppError('Forbidden', {
        statusCode: HTTP_STATUS.FORBIDDEN,
        errorCode: ERROR_CODES.FORBIDDEN,
      });
    }

    const file = await this.fileRepository.findById(row.commission_receipt_file_id);
    if (!file) {
      throw new AppError('File not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.FILE_NOT_FOUND,
      });
    }

    const absolutePath = this.resolveReceiptAbsolutePath(file.file_path);
    if (!fs.existsSync(absolutePath)) {
      throw new AppError('File not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.FILE_NOT_FOUND,
      });
    }

    return {
      absolutePath,
      mimeType: file.mime_type || 'application/octet-stream',
      fileName: this.sanitizeDownloadFilename(file.original_filename || 'receipt'),
    };
  }

  async driverHasBlockingSettlement(driverId) {
    const rows = await this.bookingRepository.findUnpaidSettlementsForDriver(driverId);
    const now = new Date();
    for (const row of rows) {
      const metadata = this.parseMetadata(row.metadata);
      if (this.isSettlementBlocking(row, metadata, now)) {
        return true;
      }
    }
    return false;
  }

  getSettlementBlockReason(driverId) {
    return this.driverHasBlockingSettlement(driverId).then((blocked) => {
      if (!blocked) return null;
      return 'Outstanding overdue or unresolved commission settlement';
    });
  }
}

module.exports = CommissionSettlementService;

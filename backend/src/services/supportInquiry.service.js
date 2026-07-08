const crypto = require('crypto');
const path = require('path');
const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const { uploadDir } = require('../config/multer');

const STATUS_VALUES = ['NEW', 'IN_PROGRESS', 'RESOLVED', 'CLOSED'];
const IMAGE_EXTENSIONS = new Set(['.jpg', '.jpeg', '.png', '.webp']);
const IMAGE_MIME_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);
const GENERIC_MIME_TYPES = new Set(['', 'application/octet-stream']);

function parseJson(value, fallback) {
  if (value == null) return fallback;
  if (typeof value === 'object') return value;
  try {
    return JSON.parse(value);
  } catch {
    return fallback;
  }
}

class SupportInquiryService {
  constructor(pool, repository) {
    this.pool = pool;
    this.repository = repository;
  }

  normalizeInput(input) {
    return {
      message: input.message.trim(),
      customerName: input.customerName?.trim() || null,
      customerPhone: input.customerPhone?.trim() || null,
      customerEmail: input.customerEmail?.trim().toLowerCase() || null,
      locale: input.locale?.trim() || null,
    };
  }

  parsePagination(query) {
    const page = Math.max(Number(query.page) || 1, 1);
    const limit = Math.min(Math.max(Number(query.limit ?? query.page_size) || 20, 1), 100);
    return { page, limit, offset: (page - 1) * limit };
  }

  parseFilters(query) {
    return {
      status: query.status || null,
      search: query.search?.trim() || null,
    };
  }

  generatePublicId() {
    const now = new Date();
    const date = now.toISOString().slice(2, 10).replace(/-/g, '');
    const suffix = crypto.randomBytes(3).toString('hex').toUpperCase();
    return `SUP-${date}-${suffix}`;
  }

  notFound() {
    throw new AppError('Support inquiry not found', {
      statusCode: HTTP_STATUS.NOT_FOUND,
      errorCode: ERROR_CODES.NOT_FOUND,
    });
  }

  invalidFileType(file, message) {
    const safeName = path.basename(String(file?.originalname || file?.filename || '').split(/[?#]/)[0]);
    throw new AppError('Invalid file type', {
      statusCode: HTTP_STATUS.BAD_REQUEST,
      errorCode: ERROR_CODES.INVALID_FILE_TYPE,
      errors: [{
        field: file?.fieldname || 'attachments',
        fileName: safeName || undefined,
        mimeType: file?.mimetype || undefined,
        allowedExtensions: Array.from(IMAGE_EXTENSIONS).map((ext) => ext.slice(1)),
        message,
      }],
    });
  }

  validateAttachment(file) {
    const safeName = path.basename(String(file.originalname || file.filename || '').split(/[?#]/)[0]);
    const ext = path.extname(safeName).toLowerCase();
    const mime = String(file.mimetype || '').toLowerCase();
    if (!IMAGE_EXTENSIONS.has(ext)) {
      this.invalidFileType(file, 'Unsupported file extension');
    }
    if (!GENERIC_MIME_TYPES.has(mime) && !IMAGE_MIME_TYPES.has(mime)) {
      this.invalidFileType(file, 'Unsupported file MIME type');
    }
  }

  async create(input, options = {}) {
    const normalized = this.normalizeInput(input);
    const files = options.files ?? [];
    files.forEach((file) => this.validateAttachment(file));

    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      let publicId = this.generatePublicId();
      let id;
      for (let attempt = 0; attempt < 3; attempt += 1) {
        try {
          id = await this.repository.create(conn, { ...normalized, publicId });
          break;
        } catch (err) {
          if (err.code !== 'ER_DUP_ENTRY' || attempt === 2) throw err;
          publicId = this.generatePublicId();
        }
      }

      for (const file of files) {
        const relativePath = file.path ? path.relative(uploadDir, file.path).replace(/\\/g, '/') : null;
        await this.repository.insertAttachment(conn, {
          inquiryId: id,
          originalFileName: path.basename(file.originalname || file.filename || 'upload'),
          mimeType: file.mimetype || null,
          fileSize: file.size ?? null,
          storagePath: relativePath,
          publicUrl: null,
        });
      }

      await conn.commit();
      const detail = await this.repository.findById(id);
      return {
        id: detail.id,
        publicId: detail.public_id,
        status: detail.status,
        createdAt: detail.created_at,
        attachmentCount: files.length,
      };
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }

  async listAdmin(query) {
    const pagination = this.parsePagination(query);
    const filters = this.parseFilters(query);
    const result = await this.repository.list(filters, pagination);
    return {
      page: pagination.page,
      pageSize: pagination.limit,
      total: result.total,
      items: result.items.map((row) => this.mapListItem(row)),
    };
  }

  async getAdminDetail(id) {
    const row = await this.repository.findById(id);
    if (!row) this.notFound();
    return this.mapDetail(row);
  }

  async updateStatus(id, status) {
    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      const affected = await this.repository.updateStatus(conn, id, status);
      if (!affected) this.notFound();
      await conn.commit();
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
    return this.getAdminDetail(id);
  }

  mapListItem(row) {
    return {
      id: row.id,
      publicId: row.public_id,
      status: row.status,
      messagePreview: row.message.length > 120 ? `${row.message.slice(0, 120)}...` : row.message,
      customerName: row.customer_name,
      customerPhone: row.customer_phone,
      customerEmail: row.customer_email,
      source: row.source,
      locale: row.locale,
      attachmentCount: Number(row.attachment_count ?? 0),
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }

  mapDetail(row) {
    const attachments = parseJson(row.attachments_json, [])
      .filter(Boolean)
      .map((item) => ({
        id: item.id,
        originalFileName: item.originalFileName,
        mimeType: item.mimeType,
        fileSize: item.fileSize,
        publicUrl: item.publicUrl,
        createdAt: item.createdAt,
      }));
    return {
      id: row.id,
      publicId: row.public_id,
      status: row.status,
      message: row.message,
      customerName: row.customer_name,
      customerPhone: row.customer_phone,
      customerEmail: row.customer_email,
      source: row.source,
      locale: row.locale,
      attachments,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }
}

SupportInquiryService.STATUS_VALUES = STATUS_VALUES;

module.exports = SupportInquiryService;

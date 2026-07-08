const crypto = require('crypto');
const fs = require('fs');
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
      kakaoId: input.kakaoId?.trim() || null,
      lineId: input.lineId?.trim() || null,
      locale: input.locale?.trim() || null,
    };
  }

  normalizeMessage(input) {
    return {
      message: input.message.trim(),
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

  generateLookupToken() {
    return crypto.randomBytes(24).toString('base64url');
  }

  hashLookupToken(token) {
    return crypto.createHash('sha256').update(String(token)).digest('hex');
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
      const lookupToken = this.generateLookupToken();
      const lookupTokenHash = this.hashLookupToken(lookupToken);
      let id;
      for (let attempt = 0; attempt < 3; attempt += 1) {
        try {
          id = await this.repository.create(conn, {
            ...normalized,
            publicId,
            lookupTokenHash,
          });
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
      await this.repository.insertMessage(conn, {
        inquiryId: id,
        senderType: 'CUSTOMER',
        senderUserId: null,
        message: normalized.message,
      });

      await conn.commit();
      const detail = await this.repository.findById(id);
      return {
        id: detail.id,
        publicId: detail.public_id,
        lookupToken,
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

  async getPublicDetail(publicId, lookupToken) {
    const token = String(lookupToken || '').trim();
    if (!token) this.notFound();
    const row = await this.repository.findByPublicId(publicId);
    if (!row || !row.lookup_token_hash) this.notFound();
    const expected = Buffer.from(row.lookup_token_hash, 'hex');
    const actual = Buffer.from(this.hashLookupToken(token), 'hex');
    if (expected.length !== actual.length || !crypto.timingSafeEqual(expected, actual)) {
      this.notFound();
    }
    return this.mapPublicDetail(row);
  }

  async addAdminMessage(id, input, actor = {}) {
    const normalized = this.normalizeMessage(input);
    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      const current = await this.repository.findById(id);
      if (!current) this.notFound();
      await this.repository.insertMessage(conn, {
        inquiryId: id,
        senderType: 'ADMIN',
        senderUserId: actor.id ?? null,
        message: normalized.message,
      });
      if (current.status === 'NEW') {
        await this.repository.updateStatus(conn, id, 'IN_PROGRESS');
      } else {
        await this.repository.touch(conn, id);
      }
      await conn.commit();
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
    return this.getAdminDetail(id);
  }

  async getAdminDetail(id) {
    const row = await this.repository.findById(id);
    if (!row) this.notFound();
    return this.mapDetail(row, { adminAttachments: true });
  }

  attachmentNotFound() {
    throw new AppError('Support inquiry attachment not found', {
      statusCode: HTTP_STATUS.NOT_FOUND,
      errorCode: ERROR_CODES.FILE_NOT_FOUND,
    });
  }

  sanitizeDownloadFilename(name) {
    const base = path.basename(String(name || 'attachment').split(/[?#]/)[0]);
    return base.replace(/[^\w.\-()[\] ]/g, '_').slice(0, 200) || 'attachment';
  }

  resolveAttachmentAbsolutePath(storagePath) {
    if (!storagePath) this.attachmentNotFound();
    const absolute = path.resolve(uploadDir, storagePath);
    const root = `${uploadDir}${path.sep}`;
    if (absolute !== uploadDir && !absolute.startsWith(root)) {
      this.attachmentNotFound();
    }
    return absolute;
  }

  async getAdminAttachmentFile(inquiryId, attachmentId) {
    const attachment = await this.repository.findAttachmentByInquiryId(
      inquiryId,
      attachmentId,
    );
    if (!attachment) this.attachmentNotFound();

    const absolutePath = this.resolveAttachmentAbsolutePath(attachment.storage_path);
    if (!fs.existsSync(absolutePath)) this.attachmentNotFound();

    return {
      absolutePath,
      mimeType: attachment.mime_type || 'application/octet-stream',
      fileName: this.sanitizeDownloadFilename(
        attachment.original_file_name || 'attachment',
      ),
    };
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
      latestMessagePreview: row.latest_message
        ? (row.latest_message.length > 120 ? `${row.latest_message.slice(0, 120)}...` : row.latest_message)
        : null,
      customerName: row.customer_name,
      customerPhone: row.customer_phone,
      customerEmail: row.customer_email,
      kakaoId: row.kakao_id,
      lineId: row.line_id,
      source: row.source,
      locale: row.locale,
      attachmentCount: Number(row.attachment_count ?? 0),
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }

  mapAttachment(item, options = {}) {
    const id = item.id;
    const inquiryId = item.inquiryId ?? item.inquiry_id;
    const mimeType = item.mimeType ?? item.mime_type;
    const isImage = String(mimeType || '').toLowerCase().startsWith('image/');
    const attachment = {
      id,
      originalFileName: item.originalFileName ?? item.original_file_name,
      mimeType,
      fileSize: item.fileSize ?? item.file_size,
      isImage,
      createdAt: item.createdAt ?? item.created_at,
    };
    if (options.adminAttachments && inquiryId && id) {
      const url = `/api/v1/admin/support/inquiries/${inquiryId}/attachments/${id}`;
      attachment.previewUrl = url;
      attachment.downloadUrl = `${url}?download=1`;
    }
    return attachment;
  }

  mapDetail(row, options = {}) {
    const rawAttachments = row.attachments ?? parseJson(row.attachments_json, []);
    const rawMessages = row.messages ?? parseJson(row.messages_json, []);
    const attachments = rawAttachments
      .filter(Boolean)
      .map((item) => this.mapAttachment(item, options));
    const messages = rawMessages
      .filter(Boolean)
      .map((item) => ({
        id: item.id,
        senderType: item.senderType ?? item.sender_type,
        senderUserId: item.senderUserId ?? item.sender_user_id,
        message: item.message,
        createdAt: item.createdAt ?? item.created_at,
      }));
    return {
      id: row.id,
      publicId: row.public_id,
      status: row.status,
      message: row.message,
      customerName: row.customer_name,
      customerPhone: row.customer_phone,
      customerEmail: row.customer_email,
      kakaoId: row.kakao_id,
      lineId: row.line_id,
      source: row.source,
      locale: row.locale,
      messages,
      attachments,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }

  mapPublicDetail(row) {
    const detail = this.mapDetail(row);
    return {
      publicId: detail.publicId,
      status: detail.status,
      messages: detail.messages,
      attachments: detail.attachments,
      createdAt: detail.createdAt,
      updatedAt: detail.updatedAt,
    };
  }
}

SupportInquiryService.STATUS_VALUES = STATUS_VALUES;

module.exports = SupportInquiryService;

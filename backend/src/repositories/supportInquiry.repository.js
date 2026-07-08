const database = require('../config/database');

class SupportInquiryRepository {
  constructor(pool = database.pool) {
    this.pool = pool;
  }

  async create(conn, data) {
    const [result] = await conn.query(
      `
        INSERT INTO support_inquiries (
          public_id, lookup_token_hash, customer_name, customer_phone,
          customer_email, kakao_id, line_id, message, status, source, locale
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'NEW', 'WEB_SUPPORT', ?)
      `,
      [
        data.publicId,
        data.lookupTokenHash,
        data.customerName,
        data.customerPhone,
        data.customerEmail,
        data.kakaoId,
        data.lineId,
        data.message,
        data.locale,
      ],
    );
    return result.insertId;
  }

  async insertMessage(conn, data) {
    const [result] = await conn.query(
      `
        INSERT INTO support_inquiry_messages (
          inquiry_id, sender_type, sender_user_id, message
        ) VALUES (?, ?, ?, ?)
      `,
      [
        data.inquiryId,
        data.senderType,
        data.senderUserId ?? null,
        data.message,
      ],
    );
    return result.insertId;
  }

  async insertAttachment(conn, data) {
    const [result] = await conn.query(
      `
        INSERT INTO support_inquiry_attachments (
          inquiry_id, original_file_name, mime_type, file_size, storage_path, public_url
        ) VALUES (?, ?, ?, ?, ?, ?)
      `,
      [
        data.inquiryId,
        data.originalFileName,
        data.mimeType,
        data.fileSize,
        data.storagePath,
        data.publicUrl,
      ],
    );
    return result.insertId;
  }

  async findById(id) {
    const [rows] = await this.pool.query(
      `
        SELECT si.*
        FROM support_inquiries si
        WHERE si.id = ? AND si.deleted_at IS NULL
        LIMIT 1
      `,
      [id],
    );
    if (!rows[0]) return null;
    return this.attachChildren(rows[0]);
  }

  async findByPublicId(publicId) {
    const [rows] = await this.pool.query(
      `
        SELECT si.*
        FROM support_inquiries si
        WHERE si.public_id = ? AND si.deleted_at IS NULL
        LIMIT 1
      `,
      [publicId],
    );
    if (!rows[0]) return null;
    return this.attachChildren(rows[0]);
  }

  async attachChildren(row) {
    const [attachments] = await this.pool.query(
      `
        SELECT
          id,
          original_file_name,
          mime_type,
          file_size,
          storage_path,
          public_url,
          created_at
        FROM support_inquiry_attachments
        WHERE inquiry_id = ? AND deleted_at IS NULL
        ORDER BY id ASC
      `,
      [row.id],
    );
    const [messages] = await this.pool.query(
      `
        SELECT
          id,
          sender_type,
          sender_user_id,
          message,
          created_at
        FROM support_inquiry_messages
        WHERE inquiry_id = ? AND deleted_at IS NULL
        ORDER BY created_at ASC, id ASC
      `,
      [row.id],
    );
    return {
      ...row,
      attachments,
      messages,
    };
  }

  async list(filters, pagination) {
    const where = ['si.deleted_at IS NULL'];
    const params = [];

    if (filters.status) {
      where.push('si.status = ?');
      params.push(filters.status);
    }
    if (filters.search) {
      where.push(`(
        si.public_id LIKE ?
        OR si.customer_name LIKE ?
        OR si.customer_phone LIKE ?
        OR si.customer_email LIKE ?
        OR si.kakao_id LIKE ?
        OR si.line_id LIKE ?
        OR si.message LIKE ?
      )`);
      const like = `%${filters.search}%`;
      params.push(like, like, like, like, like, like, like);
    }

    const whereSql = `WHERE ${where.join(' AND ')}`;
    const [countRows] = await this.pool.query(
      `SELECT COUNT(*) AS total FROM support_inquiries si ${whereSql}`,
      params,
    );
    const [rows] = await this.pool.query(
      `
        SELECT
          si.id,
          si.public_id,
          si.customer_name,
          si.customer_phone,
          si.customer_email,
          si.kakao_id,
          si.line_id,
          si.message,
          si.status,
          si.source,
          si.locale,
          si.created_at,
          si.updated_at,
          COUNT(DISTINCT sia.id) AS attachment_count,
          (
            SELECT sim.message
            FROM support_inquiry_messages sim
            WHERE sim.inquiry_id = si.id
              AND sim.deleted_at IS NULL
            ORDER BY sim.created_at DESC, sim.id DESC
            LIMIT 1
          ) AS latest_message
        FROM support_inquiries si
        LEFT JOIN support_inquiry_attachments sia
          ON sia.inquiry_id = si.id AND sia.deleted_at IS NULL
        ${whereSql}
        GROUP BY si.id
        ORDER BY si.updated_at DESC, si.id DESC
        LIMIT ? OFFSET ?
      `,
      [...params, pagination.limit, pagination.offset],
    );

    return {
      items: rows,
      total: Number(countRows[0]?.total ?? 0),
    };
  }

  async findAttachmentByInquiryId(inquiryId, attachmentId) {
    const [rows] = await this.pool.query(
      `
        SELECT
          id,
          inquiry_id,
          original_file_name,
          mime_type,
          file_size,
          storage_path,
          public_url,
          created_at
        FROM support_inquiry_attachments
        WHERE inquiry_id = ?
          AND id = ?
          AND deleted_at IS NULL
        LIMIT 1
      `,
      [inquiryId, attachmentId],
    );
    return rows[0] ?? null;
  }

  async updateStatus(conn, id, status) {
    const [result] = await conn.query(
      `
        UPDATE support_inquiries
        SET status = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ? AND deleted_at IS NULL
      `,
      [status, id],
    );
    return result.affectedRows;
  }

  async touch(conn, id) {
    await conn.query(
      `
        UPDATE support_inquiries
        SET updated_at = CURRENT_TIMESTAMP
        WHERE id = ? AND deleted_at IS NULL
      `,
      [id],
    );
  }
}

module.exports = SupportInquiryRepository;

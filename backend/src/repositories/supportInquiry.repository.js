const database = require('../config/database');

class SupportInquiryRepository {
  constructor(pool = database.pool) {
    this.pool = pool;
  }

  async create(conn, data) {
    const [result] = await conn.query(
      `
        INSERT INTO support_inquiries (
          public_id, customer_name, customer_phone, customer_email,
          message, status, source, locale
        ) VALUES (?, ?, ?, ?, ?, 'NEW', 'WEB_SUPPORT', ?)
      `,
      [
        data.publicId,
        data.customerName,
        data.customerPhone,
        data.customerEmail,
        data.message,
        data.locale,
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
        SELECT
          si.*,
          COALESCE(
            JSON_ARRAYAGG(
              CASE
                WHEN sia.id IS NULL THEN NULL
                ELSE JSON_OBJECT(
                  'id', sia.id,
                  'originalFileName', sia.original_file_name,
                  'mimeType', sia.mime_type,
                  'fileSize', sia.file_size,
                  'storagePath', sia.storage_path,
                  'publicUrl', sia.public_url,
                  'createdAt', sia.created_at
                )
              END
            ),
            JSON_ARRAY()
          ) AS attachments_json
        FROM support_inquiries si
        LEFT JOIN support_inquiry_attachments sia ON sia.inquiry_id = si.id
        WHERE si.id = ? AND si.deleted_at IS NULL
        GROUP BY si.id
        LIMIT 1
      `,
      [id],
    );
    return rows[0] || null;
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
        OR si.message LIKE ?
      )`);
      const like = `%${filters.search}%`;
      params.push(like, like, like, like, like);
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
          si.message,
          si.status,
          si.source,
          si.locale,
          si.created_at,
          si.updated_at,
          COUNT(sia.id) AS attachment_count
        FROM support_inquiries si
        LEFT JOIN support_inquiry_attachments sia ON sia.inquiry_id = si.id
        ${whereSql}
        GROUP BY si.id
        ORDER BY si.created_at DESC, si.id DESC
        LIMIT ? OFFSET ?
      `,
      [...params, pagination.limit, pagination.offset],
    );

    return {
      items: rows,
      total: Number(countRows[0]?.total ?? 0),
    };
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
}

module.exports = SupportInquiryRepository;

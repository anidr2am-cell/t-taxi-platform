const database = require('../config/database');

class FileRepository {
  constructor(pool = database.pool) {
    this.pool = pool;
  }

  async insert(conn, row) {
    const [result] = await conn.query(
      `
        INSERT INTO files (
          entity_type, entity_id, storage_provider, file_path, file_url,
          mime_type, file_size, original_filename, uploaded_by_user_id,
          created_by, updated_by
        ) VALUES (?, ?, 'LOCAL', ?, ?, ?, ?, ?, ?, ?, ?)
      `,
      [
        row.entityType,
        row.entityId,
        row.filePath,
        row.fileUrl ?? null,
        row.mimeType ?? null,
        row.fileSize ?? null,
        row.originalFilename ?? null,
        row.uploadedByUserId ?? null,
        row.createdBy ?? null,
        row.updatedBy ?? null,
      ],
    );
    return result.insertId;
  }

  async findById(fileId) {
    const [rows] = await this.pool.query(
      `
        SELECT id, entity_type, entity_id, file_path, mime_type, file_size, original_filename
        FROM files
        WHERE id = ? AND deleted_at IS NULL
        LIMIT 1
      `,
      [fileId],
    );
    return rows[0] || null;
  }

  async softDelete(conn, fileId) {
    await conn.query(
      `
        UPDATE files
        SET deleted_at = CURRENT_TIMESTAMP
        WHERE id = ? AND deleted_at IS NULL
      `,
      [fileId],
    );
  }
}

module.exports = FileRepository;

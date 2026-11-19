const fs = require('node:fs/promises');
const { pool } = require('../config/database');
const AppError = require('../utils/AppError');
const { resolveUploadAbsolutePath } = require('../utils/uploadPath.util');
const { validInsuranceDate, driverInsurance } = require('../utils/driverInsurance.util');

async function files(driverId, vehicleId, fileId = null, db = pool, storage = fs) {
  const [rows] = await db.query(`
    SELECT f.id, f.file_path, f.mime_type, m.category FROM driver_vehicles v
    JOIN drivers d ON d.id=v.driver_id AND d.deleted_at IS NULL
    JOIN (
      SELECT vf.driver_vehicle_id AS vehicle_id, vf.file_id, vf.category
      FROM driver_vehicle_files vf
      UNION
      SELECT av.id, af.file_id, af.category FROM driver_application_files af
      JOIN driver_applications da ON da.id=af.driver_application_id
        AND da.status='APPROVED' AND da.deleted_at IS NULL
      JOIN driver_vehicles av ON av.driver_id=da.approved_driver_id
        AND av.plate_number=da.vehicle_plate_number AND av.deleted_at IS NULL
    ) m ON m.vehicle_id=v.id
    JOIN files f ON f.id=m.file_id AND f.deleted_at IS NULL
    WHERE v.id=? AND v.driver_id=? AND v.deleted_at IS NULL
      AND m.category IN ('DRIVER_VEHICLE_PHOTO','DRIVER_INSURANCE_CERTIFICATE')
      AND f.mime_type IN ('image/jpeg','image/png','image/webp','application/pdf')
      AND (? IS NULL OR f.id=?) ORDER BY f.id DESC
  `, [vehicleId, driverId, fileId, fileId]);
  const result = [];
  for (const row of rows) {
    let available = false;
    try {
      const path = resolveUploadAbsolutePath(row.file_path);
      available = (await storage.stat(path)).isFile();
      if (available) await storage.access(path, 4);
    } catch (_) { /* Report missing legacy files without hiding other images. */ }
    if (fileId !== null && available) return row;
    result.push({ fileId: row.id, category: row.category, mimeType: row.mime_type, available });
  }
  if (fileId !== null) throw new AppError('File not found', { statusCode: 404, errorCode: 'FILE_NOT_FOUND' });
  return result;
}

async function updateInsurance(driverId, vehicleId, expiresOn, actor, db = pool) {
  if (expiresOn !== null && !validInsuranceDate(expiresOn)) {
    throw new AppError('Invalid insurance date', { errorCode: 'VALIDATION_ERROR' });
  }
  const conn = await db.getConnection();
  try {
    await conn.beginTransaction();
    const [[vehicle]] = await conn.query(`
      SELECT DATE_FORMAT(v.insurance_expires_on, '%Y-%m-%d') AS previousDate
      FROM driver_vehicles v JOIN drivers d ON d.id=v.driver_id AND d.deleted_at IS NULL
      WHERE v.id=? AND v.driver_id=? AND v.deleted_at IS NULL FOR UPDATE`,
    [vehicleId, driverId]);
    if (!vehicle) throw new AppError('Vehicle not found', { statusCode: 404, errorCode: 'NOT_FOUND' });
    await conn.query('UPDATE driver_vehicles SET insurance_expires_on=?, updated_at=CURRENT_TIMESTAMP WHERE id=?',
      [expiresOn, vehicleId]);
    await conn.query(`INSERT INTO audit_logs (user_id,action,entity_type,entity_id,payload)
      VALUES (?,'DRIVER_INSURANCE_UPDATED','driver_vehicle',?,?)`,
    [actor.id, vehicleId, JSON.stringify({ driverId, previousDate: vehicle.previousDate, expiresOn })]);
    await conn.commit();
    return driverInsurance(expiresOn);
  } catch (error) {
    await conn.rollback();
    throw error;
  } finally { conn.release(); }
}

module.exports = { files, updateInsurance };

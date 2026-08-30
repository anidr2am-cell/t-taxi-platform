process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const jwt = require('jsonwebtoken');
const path = require('path');
const fs = require('fs');
const app = require('../src/app');
const container = require('../src/helpers/container');
const ERROR_CODES = require('../src/constants/errorCodes');
const BookingNameSignPhotoService = require('../src/services/bookingNameSignPhoto.service');
const GuestNameSignPhotoService = require('../src/services/guestNameSignPhoto.service');
const { uploadDir } = require('../src/config/multer');
const { hashToken } = require('../src/utils/tokenHash.util');

const BOOKING_NUMBER = 'TX202607010001';

function sign(role = 'DRIVER', id = 44) {
  return jwt.sign(
    { sub: id, email: `${role.toLowerCase()}@example.com`, role, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

function createConn() {
  return {
    committed: false,
    rolledBack: false,
    released: false,
    async beginTransaction() {},
    async commit() { this.committed = true; },
    async rollback() { this.rolledBack = true; },
    release() { this.released = true; },
  };
}

const JPEG_BYTES = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]);
const PDF_BYTES = Buffer.from('%PDF-1.7\n');

function tmpUploadFile(name, content = JPEG_BYTES) {
  const filePath = path.join(uploadDir, `tmp-${Date.now()}-${Math.round(Math.random() * 1e9)}-${name}`);
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, content);
  return filePath;
}

test('driver name sign photo upload stores booking file and soft-deletes previous photo', async () => {
  const conn = createConn();
  const calls = { update: null, softDeleted: [] };
  const bookingRepository = {
    async findActiveDriverBookingByNumberForUpdate(_conn, driverUserId, bookingNumber) {
      assert.equal(driverUserId, 44);
      assert.equal(bookingNumber, BOOKING_NUMBER);
      return { id: 10, booking_number: BOOKING_NUMBER, name_sign_photo_file_id: 90 };
    },
    async updateNameSignPhotoFile(_conn, bookingId, fileId, updatedBy) {
      calls.update = { bookingId, fileId, updatedBy };
    },
  };
  const fileRepository = {
    async insert(_conn, row) {
      assert.equal(row.entityType, 'BOOKING_NAME_SIGN_PHOTO');
      assert.equal(row.entityId, 10);
      assert.equal(row.uploadedByUserId, 44);
      assert.match(row.filePath, /^bookings[\\/]+TX202607010001[\\/]+name-sign[\\/]+/);
      return 501;
    },
    async softDelete(_conn, fileId) {
      calls.softDeleted.push(fileId);
    },
  };
  const service = new BookingNameSignPhotoService(
    { async getConnection() { return conn; } },
    bookingRepository,
    fileRepository,
  );
  const source = tmpUploadFile('photo.jpg');

  const result = await service.upload(44, BOOKING_NUMBER, {
    path: source,
    mimetype: 'image/jpeg',
    size: 10,
    originalname: 'photo.jpg',
  });

  assert.equal(conn.committed, true);
  assert.deepEqual(calls.update, { bookingId: 10, fileId: 501, updatedBy: 44 });
  assert.deepEqual(calls.softDeleted, [90]);
  assert.equal(result.nameSignPhotoFileId, 501);
  assert.equal(result.nameSignPhotoUrl, `/api/v1/driver/bookings/${BOOKING_NUMBER}/name-sign-photo`);

  const stagedDir = path.join(uploadDir, 'bookings', BOOKING_NUMBER, 'name-sign');
  if (fs.existsSync(stagedDir)) fs.rmSync(stagedDir, { recursive: true, force: true });
});

test('driver name sign photo upload rejects another driver booking with FORBIDDEN', async () => {
  const conn = createConn();
  const bookingRepository = {
    async findActiveDriverBookingByNumberForUpdate() {
      return null;
    },
    async findByBookingNumberForUpdate() {
      return { id: 10, booking_number: BOOKING_NUMBER };
    },
  };
  const service = new BookingNameSignPhotoService(
    { async getConnection() { return conn; } },
    bookingRepository,
    {},
  );
  const source = tmpUploadFile('photo.jpg');

  await assert.rejects(
    () => service.upload(44, BOOKING_NUMBER, {
      path: source,
      mimetype: 'image/jpeg',
      size: 10,
      originalname: 'photo.jpg',
    }),
    (err) => err.errorCode === ERROR_CODES.FORBIDDEN,
  );
  assert.equal(conn.rolledBack, true);
});

test('driver name sign photo upload rejects non-image files', async () => {
  const service = new BookingNameSignPhotoService({}, {}, {});
  await assert.rejects(
    () => service.upload(44, BOOKING_NUMBER, {
      path: 'receipt.pdf',
      mimetype: 'application/pdf',
      size: 10,
      originalname: 'receipt.pdf',
    }),
    (err) => err.errorCode === ERROR_CODES.INVALID_FILE_TYPE,
  );
});

test('driver name sign photo file stream resolves driver-owned file', async () => {
  const relativePath = path.join('bookings', BOOKING_NUMBER, 'name-sign', 'photo.jpg');
  const absolutePath = path.join(uploadDir, relativePath);
  fs.mkdirSync(path.dirname(absolutePath), { recursive: true });
  fs.writeFileSync(absolutePath, 'driver-photo');

  const service = new BookingNameSignPhotoService({}, {
    async findNameSignPhotoFileForDriver(driverUserId, bookingNumber) {
      assert.equal(driverUserId, 44);
      assert.equal(bookingNumber, BOOKING_NUMBER);
      return {
        file_path: relativePath,
        mime_type: 'image/jpeg',
        original_filename: 'photo.jpg',
      };
    },
  }, {});

  const file = await service.getDriverFile(44, BOOKING_NUMBER);
  assert.equal(file.absolutePath, absolutePath);
  assert.equal(file.mimeType, 'image/jpeg');
  assert.equal(file.fileName, 'photo.jpg');
  fs.rmSync(path.dirname(absolutePath), { recursive: true, force: true });
});

test('driver name sign photo file stream returns FILE_NOT_FOUND when absent', async () => {
  const service = new BookingNameSignPhotoService({}, {
    async findNameSignPhotoFileForDriver() {
      return null;
    },
  }, {});

  await assert.rejects(
    () => service.getDriverFile(44, BOOKING_NUMBER),
    (err) => err.errorCode === ERROR_CODES.FILE_NOT_FOUND,
  );
});

test('guest name sign photo service uses guest token and maps public URL', async () => {
  const service = new GuestNameSignPhotoService({
    async findGuestNameSignPhotoFile(bookingId, tokenHash) {
      assert.equal(bookingId, 10);
      assert.equal(tokenHash, hashToken('guest-token'));
      return {
        file_path: 'bookings/TX202607010001/name-sign/photo.jpg',
        mime_type: 'image/jpeg',
        original_filename: 'photo.jpg',
      };
    },
  });

  assert.equal(
    service.mapNameSignPhotoUrl({ id: 10, name_sign_photo_file_id: 55 }),
    '/api/v1/public/bookings/10/name-sign-photo',
  );
  assert.equal(service.mapNameSignPhotoUrl({ id: 10, name_sign_photo_file_id: null }), null);
  const file = await service.getNameSignPhotoFile(10, 'guest-token');
  assert.equal(file.mimeType, 'image/jpeg');
});

test('guest name sign photo service rejects missing guest token', async () => {
  const service = new GuestNameSignPhotoService({});

  await assert.rejects(
    () => service.getNameSignPhotoFile(10, ''),
    (err) => err.errorCode === ERROR_CODES.BOOKING_NOT_ACCESSIBLE,
  );
});

test('guest name sign photo service returns NOT_FOUND when no photo exists', async () => {
  const service = new GuestNameSignPhotoService({
    async findGuestNameSignPhotoFile() {
      return null;
    },
  });

  await assert.rejects(
    () => service.getNameSignPhotoFile(10, 'guest-token'),
    (err) => err.errorCode === ERROR_CODES.NOT_FOUND,
  );
});

test('driver name sign photo API uploads multipart file for authenticated driver', async () => {
  let called = false;
  container.register('bookingNameSignPhotoService', () => ({
    async upload(driverUserId, bookingNumber, file) {
      called = true;
      assert.equal(driverUserId, 44);
      assert.equal(bookingNumber, BOOKING_NUMBER);
      assert.equal(file.fieldname, 'file');
      if (file.path && fs.existsSync(file.path)) fs.rmSync(file.path, { force: true });
      return {
        bookingNumber,
        nameSignPhotoFileId: 501,
        nameSignPhotoUrl: `/api/v1/driver/bookings/${bookingNumber}/name-sign-photo`,
      };
    },
  }));
  const source = tmpUploadFile('api-photo.jpg');

  const res = await request(app)
    .post(`/api/v1/driver/bookings/${BOOKING_NUMBER}/name-sign-photo`)
    .set('Authorization', `Bearer ${sign('DRIVER', 44)}`)
    .attach('file', source);

  assert.equal(res.statusCode, 200);
  assert.equal(called, true);
  assert.equal(res.body.data.nameSignPhotoFileId, 501);
  if (fs.existsSync(source)) fs.rmSync(source, { force: true });
});

test('driver name sign photo API returns INVALID_FILE_TYPE from upload validation', async () => {
  container.register('bookingNameSignPhotoService', () => ({
    async upload() {
      const AppError = require('../src/utils/AppError');
      throw new AppError('Invalid file type', {
        statusCode: 400,
        errorCode: ERROR_CODES.INVALID_FILE_TYPE,
      });
    },
  }));
  const source = tmpUploadFile('api-invalid.jpg', 'plain');

  const res = await request(app)
    .post(`/api/v1/driver/bookings/${BOOKING_NUMBER}/name-sign-photo`)
    .set('Authorization', `Bearer ${sign('DRIVER', 44)}`)
    .attach('file', source);

  assert.equal(res.statusCode, 400);
  assert.equal(res.body.error_code, ERROR_CODES.INVALID_FILE_TYPE);
  if (fs.existsSync(source)) fs.rmSync(source, { force: true });
});

test('driver name sign photo API maps multer file size errors', async () => {
  const controller = require('../src/controllers/bookingNameSignPhoto.controller');
  await new Promise((resolve, reject) => {
    controller.handleUploadError({ code: 'LIMIT_FILE_SIZE' }, {}, {}, (err) => {
      try {
        assert.equal(err.errorCode, ERROR_CODES.FILE_TOO_LARGE);
        resolve();
      } catch (assertErr) {
        reject(assertErr);
      }
    });
  });
});

test('driver name sign photo API streams file and reports missing file', async () => {
  const absolutePath = tmpUploadFile('api-stream.jpg', 'streamed-photo');
  container.register('bookingNameSignPhotoService', () => ({
    async getDriverFile(driverUserId, bookingNumber) {
      assert.equal(driverUserId, 44);
      assert.equal(bookingNumber, BOOKING_NUMBER);
      return {
        absolutePath,
        mimeType: 'image/jpeg',
        fileName: 'photo.jpg',
      };
    },
  }));

  const ok = await request(app)
    .get(`/api/v1/driver/bookings/${BOOKING_NUMBER}/name-sign-photo`)
    .set('Authorization', `Bearer ${sign('DRIVER', 44)}`);
  assert.equal(ok.statusCode, 200);
  assert.equal(ok.headers['content-type'], 'image/jpeg');

  container.register('bookingNameSignPhotoService', () => ({
    async getDriverFile() {
      const AppError = require('../src/utils/AppError');
      throw new AppError('File not found', {
        statusCode: 404,
        errorCode: ERROR_CODES.FILE_NOT_FOUND,
      });
    },
  }));
  const missing = await request(app)
    .get(`/api/v1/driver/bookings/${BOOKING_NUMBER}/name-sign-photo`)
    .set('Authorization', `Bearer ${sign('DRIVER', 44)}`);
  assert.equal(missing.statusCode, 404);
  assert.equal(missing.body.error_code, ERROR_CODES.FILE_NOT_FOUND);
  if (fs.existsSync(absolutePath)) fs.rmSync(absolutePath, { force: true });
});

test('guest name sign photo API streams image for valid guest token', async () => {
  const relativePath = path.join('bookings', BOOKING_NUMBER, 'name-sign', 'guest-photo.jpg');
  const absolutePath = path.join(uploadDir, relativePath);
  fs.mkdirSync(path.dirname(absolutePath), { recursive: true });
  fs.writeFileSync(absolutePath, 'guest-photo');
  container.register('guestNameSignPhotoService', () => ({
    async getNameSignPhotoFile(bookingId, token) {
      assert.equal(bookingId, 10);
      assert.equal(token, 'guest-token');
      return {
        filePath: relativePath,
        mimeType: 'image/jpeg',
        originalFilename: 'guest-photo.jpg',
      };
    },
  }));

  const res = await request(app)
    .get('/api/v1/public/bookings/10/name-sign-photo')
    .set('X-Guest-Access-Token', 'guest-token');
  assert.equal(res.statusCode, 200);
  assert.equal(res.headers['content-type'], 'image/jpeg');

  container.register('guestNameSignPhotoService', () => ({
    async getNameSignPhotoFile() {
      const AppError = require('../src/utils/AppError');
      throw new AppError('Name sign photo not found', {
        statusCode: 404,
        errorCode: ERROR_CODES.NOT_FOUND,
      });
    },
  }));
  const missing = await request(app)
    .get('/api/v1/public/bookings/10/name-sign-photo')
    .set('X-Guest-Access-Token', 'guest-token');
  assert.equal(missing.statusCode, 404);
  assert.equal(missing.body.error_code, ERROR_CODES.NOT_FOUND);
  fs.rmSync(path.dirname(absolutePath), { recursive: true, force: true });
});

test('guest name sign photo API requires guest token header', async () => {
  container.register('guestNameSignPhotoService', () => new GuestNameSignPhotoService({}));

  const res = await request(app)
    .get('/api/v1/public/bookings/10/name-sign-photo');

  assert.equal(res.statusCode, 403);
  assert.equal(res.body.error_code, ERROR_CODES.BOOKING_NOT_ACCESSIBLE);
});

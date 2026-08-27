process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const path = require('path');
const fs = require('fs');
const jwt = require('jsonwebtoken');
const app = require('../src/app');
const container = require('../src/helpers/container');
const GuestVehiclePhotoService = require('../src/services/guestVehiclePhoto.service');
const AppError = require('../src/utils/AppError');
const ERROR_CODES = require('../src/constants/errorCodes');
const ROLES = require('../src/constants/roles');
const { hashToken } = require('../src/utils/tokenHash.util');

const tempUploadDir = path.resolve(process.cwd(), 'uploads');
const photoRelativePath = path.join('driver-applications', 'vehicle-photo.jpg');
const photoAbsolutePath = path.join(tempUploadDir, photoRelativePath);
fs.mkdirSync(path.dirname(photoAbsolutePath), { recursive: true });
fs.writeFileSync(photoAbsolutePath, Buffer.from('fake-jpeg-bytes'));

function signCustomer(id = 42) {
  return jwt.sign(
    { sub: id, email: 'customer@example.com', role: ROLES.CUSTOMER, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

function buildPhotoService({
  customerUserId = 42,
  fileRow = {
    file_path: photoRelativePath.replace(/\\/g, '/'),
    mime_type: 'image/jpeg',
    original_filename: 'vehicle-photo.jpg',
  },
} = {}) {
  const bookingRepository = {
    async findGuestAssignedDriverVehiclePhotoFile(bookingId, tokenHash) {
      if (bookingId !== 10 || tokenHash !== hashToken('guest-token')) {
        return null;
      }
      return fileRow;
    },
    async findAssignedDriverVehiclePhotoFileByBookingId(bookingId) {
      if (bookingId !== 10) {
        return null;
      }
      return fileRow;
    },
    async findById(bookingId) {
      if (bookingId !== 10) {
        return null;
      }
      return {
        id: 10,
        booking_number: 'TX202607010001',
        customer_user_id: customerUserId,
      };
    },
  };
  const bookingService = {
    async assertCustomerOrGuestAccess(_conn, booking, authUser, guestAccessToken) {
      if (
        authUser?.role === ROLES.CUSTOMER
        && booking.customer_user_id
        && booking.customer_user_id === authUser.id
      ) {
        return;
      }

      const token = String(guestAccessToken ?? '').trim();
      if (!token) {
        throw new AppError('Booking is not accessible', {
          statusCode: 403,
          errorCode: ERROR_CODES.BOOKING_NOT_ACCESSIBLE,
        });
      }

      throw new AppError('Booking is not accessible', {
        statusCode: 403,
        errorCode: ERROR_CODES.BOOKING_NOT_ACCESSIBLE,
      });
    },
  };
  const pool = {
    async getConnection() {
      return { release() {} };
    },
  };

  return new GuestVehiclePhotoService(bookingRepository, bookingService, pool);
}

test('guest vehicle photo service maps public API path only when driver and photo exist', () => {
  const service = buildPhotoService();

  assert.equal(
    service.mapVehiclePhotoUrl({
      id: 10,
      driver_name: 'Driver A',
      driver_vehicle_photo_file_id: 55,
    }),
    '/api/v1/public/bookings/10/assigned-driver-vehicle-photo',
  );
  assert.equal(
    service.mapVehiclePhotoUrl({
      id: 10,
      driver_name: 'Driver A',
      driver_vehicle_photo_file_id: null,
    }),
    null,
  );
  assert.equal(
    service.mapVehiclePhotoUrl({
      id: 10,
      driver_name: null,
      driver_vehicle_photo_file_id: 55,
    }),
    null,
  );
});

test('guest vehicle photo service rejects missing guest token', async () => {
  const service = buildPhotoService();

  await assert.rejects(
    () => service.getAssignedDriverVehiclePhotoFile(10, ''),
    (err) => err.errorCode === 'BOOKING_NOT_ACCESSIBLE',
  );
});

test('guest vehicle photo service allows customer JWT owner without guest token', async () => {
  const service = buildPhotoService({ customerUserId: 42 });

  const file = await service.getAssignedDriverVehiclePhotoFile(
    10,
    null,
    { id: 42, role: ROLES.CUSTOMER },
  );

  assert.equal(file.mimeType, 'image/jpeg');
  assert.equal(file.filePath, photoRelativePath.replace(/\\/g, '/'));
});

test('guest vehicle photo service rejects customer JWT for another users booking', async () => {
  const service = buildPhotoService({ customerUserId: 42 });

  await assert.rejects(
    () => service.getAssignedDriverVehiclePhotoFile(
      10,
      null,
      { id: 99, role: ROLES.CUSTOMER },
    ),
    (err) => err.errorCode === ERROR_CODES.BOOKING_NOT_ACCESSIBLE,
  );
});

test('guest vehicle photo route requires guest access token header', async () => {
  container.register('guestVehiclePhotoService', () => buildPhotoService());

  const res = await request(app)
    .get('/api/v1/public/bookings/10/assigned-driver-vehicle-photo');

  assert.equal(res.statusCode, 403);
  assert.equal(res.body.error_code, 'BOOKING_NOT_ACCESSIBLE');
});

test('guest vehicle photo route streams image for valid guest token', async () => {
  container.register('guestVehiclePhotoService', () => buildPhotoService());

  const res = await request(app)
    .get('/api/v1/public/bookings/10/assigned-driver-vehicle-photo')
    .set('X-Guest-Access-Token', 'guest-token');

  assert.equal(res.statusCode, 200);
  assert.equal(res.headers['content-type'], 'image/jpeg');
  assert.equal(Buffer.from(res.body).toString(), 'fake-jpeg-bytes');
  assert.ok(!JSON.stringify(res.body).includes('driver-applications'));
});

test('guest vehicle photo route streams image for customer JWT owner', async () => {
  container.register('guestVehiclePhotoService', () => buildPhotoService({ customerUserId: 42 }));

  const res = await request(app)
    .get('/api/v1/public/bookings/10/assigned-driver-vehicle-photo')
    .set('Authorization', `Bearer ${signCustomer(42)}`);

  assert.equal(res.statusCode, 200);
  assert.equal(res.headers['content-type'], 'image/jpeg');
  assert.equal(Buffer.from(res.body).toString(), 'fake-jpeg-bytes');
});

test('guest vehicle photo route rejects customer JWT for another users booking', async () => {
  container.register('guestVehiclePhotoService', () => buildPhotoService({ customerUserId: 42 }));

  const res = await request(app)
    .get('/api/v1/public/bookings/10/assigned-driver-vehicle-photo')
    .set('Authorization', `Bearer ${signCustomer(99)}`);

  assert.equal(res.statusCode, 403);
  assert.equal(res.body.error_code, 'BOOKING_NOT_ACCESSIBLE');
});

test('guest vehicle photo route returns not found when photo unavailable', async () => {
  container.register('guestVehiclePhotoService', () => buildPhotoService({ fileRow: null }));

  const res = await request(app)
    .get('/api/v1/public/bookings/10/assigned-driver-vehicle-photo')
    .set('X-Guest-Access-Token', 'guest-token');

  assert.equal(res.statusCode, 404);
  assert.equal(res.body.error_code, 'NOT_FOUND');
});

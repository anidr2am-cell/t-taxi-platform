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
const app = require('../src/app');
const container = require('../src/helpers/container');
const GuestVehiclePhotoService = require('../src/services/guestVehiclePhoto.service');
const { hashToken } = require('../src/utils/tokenHash.util');

const tempUploadDir = path.resolve(process.cwd(), 'uploads');
const photoRelativePath = path.join('driver-applications', 'vehicle-photo.jpg');
const photoAbsolutePath = path.join(tempUploadDir, photoRelativePath);
fs.mkdirSync(path.dirname(photoAbsolutePath), { recursive: true });
fs.writeFileSync(photoAbsolutePath, Buffer.from('fake-jpeg-bytes'));

function buildPhotoService(fileRow = {
  file_path: photoRelativePath.replace(/\\/g, '/'),
  mime_type: 'image/jpeg',
  original_filename: 'vehicle-photo.jpg',
}) {
  const bookingRepository = {
    async findGuestAssignedDriverVehiclePhotoFile(bookingId, tokenHash) {
      if (bookingId !== 10 || tokenHash !== hashToken('guest-token')) {
        return null;
      }
      return fileRow;
    },
  };
  return new GuestVehiclePhotoService(bookingRepository);
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

test('guest vehicle photo route returns not found when photo unavailable', async () => {
  container.register('guestVehiclePhotoService', () => buildPhotoService(null));

  const res = await request(app)
    .get('/api/v1/public/bookings/10/assigned-driver-vehicle-photo')
    .set('X-Guest-Access-Token', 'guest-token');

  assert.equal(res.statusCode, 404);
  assert.equal(res.body.error_code, 'NOT_FOUND');
});

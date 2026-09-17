process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';
process.env.SOCIAL_TOKEN_ENCRYPTION_KEY = process.env.SOCIAL_TOKEN_ENCRYPTION_KEY
  || Buffer.alloc(32, 3).toString('base64');

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const jwt = require('jsonwebtoken');
const request = require('supertest');
const ROLES = require('../src/constants/roles');
const container = require('../src/helpers/container');
const app = require('../src/app');
const GuestVehiclePhotoService = require('../src/services/guestVehiclePhoto.service');
const { hashToken } = require('../src/utils/tokenHash.util');
const {
  authMiddleware,
  optionalAuthMiddleware,
} = require('../src/middlewares/auth.middleware');

const vehiclePhotoRelativePath = 'driver-applications/vehicle-photo.jpg';
const vehiclePhotoAbsolutePath = path.join(
  path.resolve(process.cwd(), 'uploads'),
  vehiclePhotoRelativePath,
);
fs.mkdirSync(path.dirname(vehiclePhotoAbsolutePath), { recursive: true });
fs.writeFileSync(vehiclePhotoAbsolutePath, Buffer.from('fake-jpeg-bytes'));

function signCustomer(id = 42, expiresIn = '1h') {
  return jwt.sign(
    { sub: id, email: 'customer@example.com', role: ROLES.CUSTOMER, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn },
  );
}

function runMiddleware(middleware, headers = {}) {
  return new Promise((resolve, reject) => {
    const req = { headers };
    const res = {};
    middleware(req, res, (err) => {
      if (err) {
        reject(err);
        return;
      }
      resolve(req);
    });
  });
}

test('optionalAuthMiddleware leaves req.user null when Authorization header is missing', async () => {
  const req = await runMiddleware(optionalAuthMiddleware, {});
  assert.equal(req.user, null);
});

test('optionalAuthMiddleware sets req.user for valid JWT', async () => {
  const token = signCustomer(42);
  const req = await runMiddleware(optionalAuthMiddleware, {
    authorization: `Bearer ${token}`,
  });
  assert.equal(req.user.id, 42);
  assert.equal(req.user.role, ROLES.CUSTOMER);
});

test('optionalAuthMiddleware sets req.user null for expired JWT instead of rejecting', async () => {
  const token = signCustomer(42, '-1h');
  const req = await runMiddleware(optionalAuthMiddleware, {
    authorization: `Bearer ${token}`,
  });
  assert.equal(req.user, null);
});

test('authMiddleware still rejects expired JWT', async () => {
  const token = signCustomer(42, '-1h');
  await assert.rejects(
    () => runMiddleware(authMiddleware, { authorization: `Bearer ${token}` }),
    (err) => err.statusCode === 401,
  );
});

test('optionalAuth route accepts expired JWT with valid guest token', async () => {
  container.register('guestVehiclePhotoService', () => new GuestVehiclePhotoService({
    async findGuestAssignedDriverVehiclePhotoFile(bookingId, tokenHash) {
      if (bookingId === 10 && tokenHash === hashToken('guest-token')) {
        return {
          file_path: vehiclePhotoRelativePath,
          mime_type: 'image/jpeg',
          original_filename: 'vehicle-photo.jpg',
        };
      }
      return null;
    },
    async findAssignedDriverVehiclePhotoFileByBookingId() { return null; },
    async findById() { return null; },
  }));

  const res = await request(app)
    .get('/api/v1/public/bookings/10/assigned-driver-vehicle-photo')
    .set('Authorization', `Bearer ${signCustomer(42, '-1h')}`)
    .set('X-Guest-Access-Token', 'guest-token');

  assert.equal(res.statusCode, 200);
});

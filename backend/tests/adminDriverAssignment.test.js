process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const request = require('supertest');

const app = require('../src/app');
const container = require('../src/helpers/container');
const DriverCandidateScoringService = require('../src/services/driverCandidateScoring.service');
const { haversineKm } = require('../src/utils/geo.util');
const ERROR_CODES = require('../src/constants/errorCodes');
const BOOKING_STATUS = require('../src/constants/reservationStatus');

function sign(role = 'ADMIN', id = 1) {
  return jwt.sign(
    { sub: id, email: `${role.toLowerCase()}@example.com`, role, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

const booking = {
  id: 10,
  booking_number: 'TX202607010001',
  status: BOOKING_STATUS.CONFIRMED,
  vehicle_type_id: 2,
  vehicle_type_code: 'SUV',
  origin_lat: 13.69,
  origin_lng: 100.75,
  scheduled_pickup_at: '2026-07-01 09:30:00',
};

function driver(overrides = {}) {
  return {
    id: 7,
    name: 'Somchai',
    status: 'ACTIVE',
    is_online: 1,
    is_active: 1,
    user_is_active: 1,
    primary_vehicle_type_id: 2,
    primary_vehicle_type_code: 'SUV',
    primary_vehicle_id: 100,
    vehicle_type_id: 2,
    current_lat: 13.70,
    current_lng: 100.76,
    location_updated_at: new Date().toISOString(),
    active_assignment_count: 0,
    average_rating: 4.8,
    assignments_today_count: 0,
    last_assigned_at: '2026-06-20T08:00:00.000Z',
    schedule_conflict_count: 0,
    ...overrides,
  };
}

test('haversineKm returns distance for valid coordinates', () => {
  const km = haversineKm(13.69, 100.75, 13.70, 100.76);
  assert.ok(km != null && km > 0 && km < 20);
});

test('vehicle mismatch excludes candidate', () => {
  const service = new DriverCandidateScoringService();
  const result = service.buildCandidate(
    driver({ primary_vehicle_type_id: 1, vehicle_type_id: 1, primary_vehicle_type_code: 'SEDAN' }),
    booking,
  );
  assert.equal(result.eligible, false);
  assert.ok(result.exclusionReasons.includes('VEHICLE_MISMATCH'));
});

test('offline driver excluded when online required', () => {
  const service = new DriverCandidateScoringService();
  const result = service.buildCandidate(driver({ is_online: 0, status: 'OFFLINE' }), booking);
  assert.equal(result.eligible, false);
  assert.ok(result.exclusionReasons.includes('OFFLINE'));
});

test('eligible driver receives score and reasons', () => {
  const service = new DriverCandidateScoringService();
  const result = service.buildCandidate(driver(), booking);
  assert.equal(result.eligible, true);
  assert.ok(result.score > 0);
  assert.ok(result.reasons.includes('VEHICLE_MATCH'));
  assert.ok(result.reasons.includes('ONLINE'));
});

test('tie-breaker prefers higher score first', () => {
  const service = new DriverCandidateScoringService();
  const higher = { driverId: 1, score: 90, activeJobCount: 0, distanceKm: 5, lastAssignedAt: null };
  const lower = { driverId: 2, score: 80, activeJobCount: 0, distanceKm: 1, lastAssignedAt: null };
  assert.ok(service.compareCandidates(higher, lower) < 0);
});

test('tie-breaker prefers fewer active jobs when score is equal', () => {
  const service = new DriverCandidateScoringService();
  const fewerJobs = {
    driverId: 1,
    score: 80,
    activeJobCount: 0,
    distanceKm: 2,
    lastAssignedAt: null,
  };
  const moreJobs = {
    driverId: 2,
    score: 80,
    activeJobCount: 1,
    distanceKm: 1,
    lastAssignedAt: null,
  };
  assert.ok(service.compareCandidates(fewerJobs, moreJobs) < 0);
});

test('tie-breaker prefers closer distance when score and active jobs are equal', () => {
  const service = new DriverCandidateScoringService();
  const closer = { driverId: 1, score: 80, activeJobCount: 0, distanceKm: 2, lastAssignedAt: null };
  const farther = { driverId: 2, score: 80, activeJobCount: 0, distanceKm: 8, lastAssignedAt: null };
  assert.ok(service.compareCandidates(closer, farther) < 0);
});

test('tie-breaker puts null distance after known distance', () => {
  const service = new DriverCandidateScoringService();
  const withDistance = { driverId: 1, score: 80, activeJobCount: 0, distanceKm: 20, lastAssignedAt: null };
  const noDistance = { driverId: 2, score: 80, activeJobCount: 0, distanceKm: null, lastAssignedAt: null };
  assert.ok(service.compareCandidates(withDistance, noDistance) < 0);
  assert.ok(service.compareCandidates(noDistance, withDistance) > 0);
});

test('tie-breaker prefers older lastAssignedAt when score jobs and distance are equal', () => {
  const service = new DriverCandidateScoringService();
  const older = {
    driverId: 2,
    score: 80,
    activeJobCount: 0,
    distanceKm: 3,
    lastAssignedAt: '2026-01-01T08:00:00.000Z',
  };
  const newer = {
    driverId: 1,
    score: 80,
    activeJobCount: 0,
    distanceKm: 3,
    lastAssignedAt: '2026-06-01T08:00:00.000Z',
  };
  assert.ok(service.compareCandidates(older, newer) < 0);
});

test('tie-breaker treats null lastAssignedAt as never assigned (oldest for fair rotation)', () => {
  const service = new DriverCandidateScoringService();
  const neverAssigned = { driverId: 1, score: 80, activeJobCount: 0, distanceKm: 3, lastAssignedAt: null };
  const recentlyAssigned = {
    driverId: 2,
    score: 80,
    activeJobCount: 0,
    distanceKm: 3,
    lastAssignedAt: '2026-06-20T08:00:00.000Z',
  };
  assert.ok(service.compareCandidates(neverAssigned, recentlyAssigned) < 0);
});

test('tie-breaker uses lower driverId when all other keys are equal', () => {
  const service = new DriverCandidateScoringService();
  const lowerId = { driverId: 1, score: 80, activeJobCount: 0, distanceKm: 3, lastAssignedAt: null };
  const higherId = { driverId: 5, score: 80, activeJobCount: 0, distanceKm: 3, lastAssignedAt: null };
  assert.ok(service.compareCandidates(lowerId, higherId) < 0);
  assert.equal(service.compareCandidates(lowerId, higherId), service.compareCandidates(higherId, lowerId) * -1);
});

test('rankCandidates produces deterministic order across full tie-breaker chain', () => {
  const service = new DriverCandidateScoringService();
  const input = [
    { driverId: 4, score: 70, activeJobCount: 0, distanceKm: 1, lastAssignedAt: null, eligible: true },
    { driverId: 3, score: 90, activeJobCount: 1, distanceKm: 1, lastAssignedAt: null, eligible: true },
    { driverId: 2, score: 80, activeJobCount: 0, distanceKm: null, lastAssignedAt: '2026-06-01T08:00:00.000Z', eligible: true },
    { driverId: 1, score: 80, activeJobCount: 0, distanceKm: 5, lastAssignedAt: '2026-06-01T08:00:00.000Z', eligible: true },
    { driverId: 5, score: 80, activeJobCount: 0, distanceKm: 5, lastAssignedAt: '2026-01-01T08:00:00.000Z', eligible: true },
    { driverId: 6, score: 80, activeJobCount: 0, distanceKm: 5, lastAssignedAt: '2026-01-01T08:00:00.000Z', eligible: true },
  ];
  const { eligible } = service.rankCandidates(input);
  assert.deepEqual(
    eligible.map((row) => row.driverId),
    [3, 5, 6, 1, 2, 4],
  );
  assert.deepEqual(
    service.rankCandidates(input).eligible.map((row) => row.driverId),
    eligible.map((row) => row.driverId),
  );
});

test('ADMIN can fetch driver candidates', async () => {
  container.register('adminDispatchService', () => ({
    async getDriverCandidates() {
      return {
        bookingId: 10,
        bookingNumber: 'TX202607010001',
        recommendedDriverId: 7,
        assignmentVersion: 0,
        candidates: [{
          driverId: 7,
          displayName: 'Somchai',
          vehicleTypeCode: 'SUV',
          online: true,
          activeJobCount: 0,
          distanceKm: 3.2,
          locationFresh: true,
          score: 92,
          reasons: ['VEHICLE_MATCH', 'ONLINE'],
          eligible: true,
        }],
        excluded: [{ driverId: 9, displayName: 'Offline', reasons: ['OFFLINE'] }],
      };
    },
  }));

  const res = await request(app)
    .get('/api/v1/admin/bookings/TX202607010001/driver-candidates')
    .set('Authorization', `Bearer ${sign('ADMIN')}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.data.recommendedDriverId, 7);
  assert.equal(res.body.data.candidates.length, 1);
  assert.ok(!JSON.stringify(res.body).includes('customerPhone'));
});

test('DRIVER cannot fetch driver candidates', async () => {
  container.register('adminDispatchService', () => ({
    async getDriverCandidates() {
      return { candidates: [] };
    },
  }));

  const res = await request(app)
    .get('/api/v1/admin/bookings/TX202607010001/driver-candidates')
    .set('Authorization', `Bearer ${sign('DRIVER', 9)}`);

  assert.equal(res.status, 403);
});

test('auto assign uses top candidate', async () => {
  let assignPayload;
  container.register('adminDispatchService', () => ({
    async autoAssignDriver(_bookingNumber, input) {
      assignPayload = input;
      return {
        assignmentId: 55,
        bookingStatus: BOOKING_STATUS.DRIVER_ASSIGNED,
        driver: { driverId: 7 },
      };
    },
  }));

  const res = await request(app)
    .post('/api/v1/admin/bookings/TX202607010001/auto-assign')
    .set('Authorization', `Bearer ${sign('ADMIN')}`)
    .send({ useTopCandidate: true, expectedAssignmentVersion: 0 });

  assert.equal(res.status, 200);
  assert.equal(assignPayload.useTopCandidate, true);
});

test('auto assign rejects stale assignment version', async () => {
  container.register('adminDispatchService', () => ({
    async autoAssignDriver() {
      const AppError = require('../src/utils/AppError');
      const HTTP_STATUS = require('../src/constants/httpStatus');
      throw new AppError('Assignment conflict', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.ASSIGNMENT_CONFLICT,
      });
    },
  }));

  const res = await request(app)
    .post('/api/v1/admin/bookings/TX202607010001/auto-assign')
    .set('Authorization', `Bearer ${sign('ADMIN')}`)
    .send({ driverId: 7, expectedAssignmentVersion: 0 });

  assert.equal(res.status, 409);
  assert.equal(res.body.error_code, ERROR_CODES.ASSIGNMENT_CONFLICT);
});

process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const request = require('supertest');
const AdminBookingNoteService = require('../src/services/adminBookingNote.service');
const AdminBookingNoteRepository = require('../src/repositories/adminBookingNote.repository');
const container = require('../src/helpers/container');
const app = require('../src/app');

function sign(role = 'ADMIN', id = 7) {
  return jwt.sign(
    { sub: id, id, email: 'admin@example.com', role, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

function serviceFixture() {
  const calls = { inserted: null, activity: null, committed: false };
  const conn = {
    async beginTransaction() {},
    async commit() { calls.committed = true; },
    async rollback() {},
    release() {},
  };
  const notes = {
    async findBookingByNumber(number) {
      return number === 'MISSING' ? null : { id: 11, booking_number: number, status: 'PENDING', commission_status: 'DUE' };
    },
    async listByBookingId() {
      return [{ id: 1, note_text: 'First', admin_user_id: 7, author_name: 'Admin A', created_at: '2026-07-12 10:00:00' }];
    },
    async countByBookingId() { return 1; },
    async insert(_conn, input) { calls.inserted = input; return 9; },
    async findById() {
      return { id: 9, note_text: calls.inserted.text, admin_user_id: calls.inserted.adminUserId, author_name: 'Admin A', created_at: '2026-07-12 10:30:00' };
    },
  };
  const bookings = {
    async insertActivityLog(_conn, _bookingId, activity) { calls.activity = activity; },
  };
  return { service: new AdminBookingNoteService({ async getConnection() { return conn; } }, notes, bookings), calls };
}

test('admin lists booking notes with author and pagination', async () => {
  const { service } = serviceFixture();
  const result = await service.list('TX1', { page: 1, limit: 20 }, { id: 7, role: 'ADMIN' });
  assert.equal(result.total, 1);
  assert.equal(result.items[0].author.name, 'Admin A');
});

test('note creation uses JWT actor and does not change booking or settlement state', async () => {
  const { service, calls } = serviceFixture();
  const result = await service.create('TX1', { text: '  Operational note  ', adminUserId: 99 }, { id: 7, role: 'SUPER_ADMIN' });
  assert.equal(calls.inserted.adminUserId, 7);
  assert.equal(calls.inserted.text, 'Operational note');
  assert.equal(calls.activity.payload.noteId, 9);
  assert.equal(calls.activity.payload.text, undefined);
  assert.equal(calls.committed, true);
  assert.equal(result.author.id, 7);
});

test('missing booking returns BOOKING_NOT_FOUND', async () => {
  const { service } = serviceFixture();
  await assert.rejects(
    service.list('MISSING', {}, { id: 7, role: 'ADMIN' }),
    (error) => error.errorCode === 'BOOKING_NOT_FOUND' && error.statusCode === 404,
  );
});

test('non-admin service access is forbidden', async () => {
  const { service } = serviceFixture();
  await assert.rejects(service.list('TX1', {}, { id: 3, role: 'DRIVER' }), (error) => error.statusCode === 403);
});

test('repository uses bound parameters for list and insert', async () => {
  const queries = [];
  const pool = { async query(sql, params) { queries.push({ sql, params }); return [[{ total: 0 }]]; } };
  const repo = new AdminBookingNoteRepository(pool);
  await repo.listByBookingId(11, { limit: 20, offset: 0 });
  await repo.insert(pool, { bookingId: 11, adminUserId: 7, text: 'Note' });
  assert.deepEqual(queries[0].params, [11, 20, 0]);
  assert.deepEqual(queries[1].params, [11, 7, 'Note']);
});

test('notes routes enforce role and body validation', async () => {
  container.register('adminBookingNoteService', () => ({
    async list() { return { page: 1, pageSize: 20, total: 0, items: [] }; },
    async create(_number, body, actor) { return { id: 1, text: body.text, author: { id: actor.id } }; },
  }));
  const bookingNumber = 'TX202607120001';
  const unauthenticated = await request(app).get(`/api/v1/admin/bookings/${bookingNumber}/notes`);
  assert.equal(unauthenticated.status, 401);
  const driver = await request(app).get(`/api/v1/admin/bookings/${bookingNumber}/notes`).set('Authorization', `Bearer ${sign('DRIVER', 3)}`);
  assert.equal(driver.status, 403);
  const blank = await request(app).post(`/api/v1/admin/bookings/${bookingNumber}/notes`).set('Authorization', `Bearer ${sign()}`).send({ text: '   ' });
  assert.equal(blank.status, 400);
  const tooLong = await request(app).post(`/api/v1/admin/bookings/${bookingNumber}/notes`).set('Authorization', `Bearer ${sign()}`).send({ text: 'x'.repeat(1001) });
  assert.equal(tooLong.status, 400);
  const forgedActor = await request(app)
    .post(`/api/v1/admin/bookings/${bookingNumber}/notes`)
    .set('Authorization', `Bearer ${sign()}`)
    .send({ text: 'Valid note', adminUserId: 99 });
  assert.equal(forgedActor.status, 400);
  const exact = await request(app).post(`/api/v1/admin/bookings/${bookingNumber}/notes`).set('Authorization', `Bearer ${sign()}`).send({ text: 'x'.repeat(1000) });
  assert.equal(exact.status, 201);
});

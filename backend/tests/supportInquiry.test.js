process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test, describe, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');

const app = require('../src/app');
const container = require('../src/helpers/container');
const ERROR_CODES = require('../src/constants/errorCodes');
const SupportInquiryService = require('../src/services/supportInquiry.service');

function registerAuth(role = 'ADMIN') {
  container.register('authService', () => ({
    verifyAccessToken() {
      return { id: 7, role, email: 'admin@test.local' };
    },
  }));
}

describe('Support inquiry routes', () => {
  beforeEach(() => {
    container.register('supportInquiryService', () => ({
      async create(body, options) {
        return {
          publicId: 'SUP-260708-ABC123',
          status: 'NEW',
          createdAt: '2026-07-08 12:00:00',
          attachmentCount: options.files?.length ?? 0,
          echo: body.message,
        };
      },
      async listAdmin() {
        return {
          page: 1,
          pageSize: 20,
          total: 1,
          items: [{
            id: 1,
            publicId: 'SUP-260708-ABC123',
            status: 'NEW',
            messagePreview: 'Airport pickup question',
            attachmentCount: 0,
            createdAt: '2026-07-08 12:00:00',
          }],
        };
      },
      async getAdminDetail(id) {
        return {
          id,
          publicId: 'SUP-260708-ABC123',
          status: 'NEW',
          message: 'Airport pickup question',
          attachments: [],
        };
      },
      async updateStatus(id, status) {
        return {
          id,
          publicId: 'SUP-260708-ABC123',
          status,
          message: 'Airport pickup question',
          attachments: [],
        };
      },
    }));
  });

  test('POST /api/v1/support/inquiries creates inquiry without auth', async () => {
    const res = await request(app)
      .post('/api/v1/support/inquiries')
      .send({
        message: 'Airport pickup booking question',
        customerName: 'Test Customer',
        customerPhone: '+66810000000',
        locale: 'ko',
      })
      .expect(201);

    assert.equal(res.body.success, true);
    assert.equal(res.body.data.publicId, 'SUP-260708-ABC123');
    assert.equal(res.body.data.status, 'NEW');
  });

  test('empty support inquiry message is rejected', async () => {
    const res = await request(app)
      .post('/api/v1/support/inquiries')
      .send({ message: '   ' })
      .expect(400);

    assert.equal(res.body.success, false);
    assert.equal(res.body.error_code, ERROR_CODES.VALIDATION_ERROR);
  });

  test('too long support inquiry message is rejected', async () => {
    const res = await request(app)
      .post('/api/v1/support/inquiries')
      .send({ message: 'x'.repeat(5001) })
      .expect(400);

    assert.equal(res.body.error_code, ERROR_CODES.VALIDATION_ERROR);
  });

  test('admin support inquiry list requires authentication', async () => {
    await request(app)
      .get('/api/v1/admin/support/inquiries')
      .expect(401);
  });

  test('admin can list support inquiries', async () => {
    registerAuth('ADMIN');

    const res = await request(app)
      .get('/api/v1/admin/support/inquiries')
      .set('Authorization', 'Bearer admin-token')
      .expect(200);

    assert.equal(res.body.success, true);
    assert.equal(res.body.data.items[0].publicId, 'SUP-260708-ABC123');
  });

  test('admin can read support inquiry detail', async () => {
    registerAuth('SUPER_ADMIN');

    const res = await request(app)
      .get('/api/v1/admin/support/inquiries/1')
      .set('Authorization', 'Bearer admin-token')
      .expect(200);

    assert.equal(res.body.data.message, 'Airport pickup question');
  });

  test('admin can update support inquiry status', async () => {
    registerAuth('ADMIN');

    const res = await request(app)
      .patch('/api/v1/admin/support/inquiries/1/status')
      .set('Authorization', 'Bearer admin-token')
      .send({ status: 'IN_PROGRESS' })
      .expect(200);

    assert.equal(res.body.data.status, 'IN_PROGRESS');
  });
});

describe('SupportInquiryService', () => {
  test('image attachments are accepted and mapped to metadata', async () => {
    const calls = [];
    const conn = {
      async beginTransaction() { calls.push('begin'); },
      async commit() { calls.push('commit'); },
      async rollback() { calls.push('rollback'); },
      release() { calls.push('release'); },
    };
    const pool = { async getConnection() { return conn; } };
    const repository = {
      async create(_conn, data) {
        calls.push(['create', data.publicId, data.message]);
        return 9;
      },
      async insertAttachment(_conn, data) {
        calls.push(['attachment', data.originalFileName, data.mimeType]);
        return 1;
      },
      async findById() {
        return {
          id: 9,
          public_id: 'SUP-260708-ABC123',
          status: 'NEW',
          created_at: '2026-07-08 12:00:00',
        };
      },
    };

    const result = await new SupportInquiryService(pool, repository).create(
      { message: ' Need pickup help ', locale: 'ko' },
      {
        files: [{
          fieldname: 'attachments',
          originalname: 'ticket.JPG',
          filename: 'stored.JPG',
          path: 'C:/TTaxi/backend/uploads/2026-07-08/stored.JPG',
          mimetype: 'application/octet-stream',
          size: 123,
        }],
      },
    );

    assert.equal(result.publicId, 'SUP-260708-ABC123');
    assert.equal(result.attachmentCount, 1);
    assert.deepEqual(calls[0], 'begin');
    assert.equal(calls.some((call) => Array.isArray(call) && call[0] === 'attachment'), true);
  });

  test('non-image support attachment is rejected', async () => {
    const service = new SupportInquiryService({}, {});

    assert.throws(
      () => service.validateAttachment({
        fieldname: 'attachments',
        originalname: 'document.pdf',
        mimetype: 'application/pdf',
      }),
      /Invalid file type/,
    );
  });
});

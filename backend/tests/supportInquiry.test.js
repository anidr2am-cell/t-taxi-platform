process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test, describe, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const request = require('supertest');

const app = require('../src/app');
const container = require('../src/helpers/container');
const ERROR_CODES = require('../src/constants/errorCodes');
const SupportInquiryService = require('../src/services/supportInquiry.service');
const AppError = require('../src/utils/AppError');
const HTTP_STATUS = require('../src/constants/httpStatus');
const { uploadDir } = require('../src/config/multer');

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
          lookupToken: 'lookup-token',
          status: 'NEW',
          createdAt: '2026-07-08 12:00:00',
          attachmentCount: options.files?.length ?? 0,
          echo: body.message,
          contact: {
            kakaoId: body.kakaoId,
            lineId: body.lineId,
          },
        };
      },
      async getPublicDetail(publicId, token) {
        if (token !== 'lookup-token') {
          const AppError = require('../src/utils/AppError');
          throw new AppError('Support inquiry not found', {
            statusCode: 404,
            errorCode: ERROR_CODES.NOT_FOUND,
          });
        }
        return {
          publicId,
          status: 'NEW',
          messages: [{
            id: 1,
            senderType: 'CUSTOMER',
            message: 'Airport pickup question',
            createdAt: '2026-07-08 12:00:00',
          }],
          attachments: [],
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
            latestMessagePreview: 'Airport pickup question',
            kakaoId: 'test-kakao',
            lineId: 'test-line',
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
          kakaoId: 'test-kakao',
          lineId: 'test-line',
          messages: [{
            id: 1,
            senderType: 'CUSTOMER',
            message: 'Airport pickup question',
          }],
          attachments: [],
        };
      },
      async updateStatus(id, status) {
        return {
          id,
          publicId: 'SUP-260708-ABC123',
          status,
          message: 'Airport pickup question',
          messages: [],
          attachments: [],
        };
      },
      async addAdminMessage(id, body) {
        return {
          id,
          publicId: 'SUP-260708-ABC123',
          status: 'IN_PROGRESS',
          message: 'Airport pickup question',
          messages: [
            { id: 1, senderType: 'CUSTOMER', message: 'Airport pickup question' },
            { id: 2, senderType: 'ADMIN', message: body.message },
          ],
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
        kakaoId: 'test-kakao',
        lineId: 'test-line',
        locale: 'ko',
      })
      .expect(201);

    assert.equal(res.body.success, true);
    assert.equal(res.body.data.publicId, 'SUP-260708-ABC123');
    assert.equal(res.body.data.lookupToken, 'lookup-token');
    assert.equal(res.body.data.status, 'NEW');
  });

  test('public inquiry detail requires lookup token', async () => {
    await request(app)
      .get('/api/v1/support/inquiries/SUP-260708-ABC123')
      .expect(404);
  });

  test('public inquiry detail returns messages with valid lookup token', async () => {
    const res = await request(app)
      .get('/api/v1/support/inquiries/SUP-260708-ABC123')
      .query({ token: 'lookup-token' })
      .expect(200);

    assert.equal(res.body.data.publicId, 'SUP-260708-ABC123');
    assert.equal(res.body.data.messages[0].senderType, 'CUSTOMER');
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
    assert.equal(res.body.data.items[0].kakaoId, 'test-kakao');
  });

  test('admin can read support inquiry detail', async () => {
    registerAuth('SUPER_ADMIN');

    const res = await request(app)
      .get('/api/v1/admin/support/inquiries/1')
      .set('Authorization', 'Bearer admin-token')
      .expect(200);

    assert.equal(res.body.data.message, 'Airport pickup question');
    assert.equal(res.body.data.messages[0].senderType, 'CUSTOMER');
  });

  test('admin detail returns safe attachment metadata without storage path', async () => {
    container.register('supportInquiryService', () => ({
      async getAdminDetail(id) {
        return {
          id,
          publicId: 'SUP-260708-ABC123',
          status: 'NEW',
          message: 'Airport pickup question',
          messages: [],
          attachments: [{
            id: 3,
            originalFileName: 'ticket.jpg',
            mimeType: 'image/jpeg',
            fileSize: 123,
            isImage: true,
            previewUrl: '/api/v1/admin/support/inquiries/1/attachments/3',
            downloadUrl: '/api/v1/admin/support/inquiries/1/attachments/3?download=1',
          }],
        };
      },
    }));
    registerAuth('ADMIN');

    const res = await request(app)
      .get('/api/v1/admin/support/inquiries/1')
      .set('Authorization', 'Bearer admin-token')
      .expect(200);

    const attachment = res.body.data.attachments[0];
    assert.equal(attachment.originalFileName, 'ticket.jpg');
    assert.equal(attachment.isImage, true);
    assert.equal(attachment.previewUrl, '/api/v1/admin/support/inquiries/1/attachments/3');
    assert.equal(Object.hasOwn(attachment, 'storagePath'), false);
    assert.equal(Object.hasOwn(attachment, 'storage_path'), false);
  });

  test('admin attachment fetch requires admin role', async () => {
    await request(app)
      .get('/api/v1/admin/support/inquiries/1/attachments/3')
      .expect(401);

    registerAuth('DRIVER');
    await request(app)
      .get('/api/v1/admin/support/inquiries/1/attachments/3')
      .set('Authorization', 'Bearer driver-token')
      .expect(403);
  });

  test('admin can fetch inline and download support attachment', async () => {
    const filePath = path.join(uploadDir, 'support-test-attachment.png');
    fs.writeFileSync(filePath, Buffer.from([0x89, 0x50, 0x4e, 0x47]));
    container.register('supportInquiryService', () => ({
      async getAdminAttachmentFile(inquiryId, attachmentId) {
        assert.equal(inquiryId, 1);
        assert.equal(attachmentId, 3);
        return {
          absolutePath: filePath,
          mimeType: 'image/png',
          fileName: 'ticket.png',
        };
      },
    }));
    registerAuth('SUPER_ADMIN');

    try {
      const inline = await request(app)
        .get('/api/v1/admin/support/inquiries/1/attachments/3')
        .set('Authorization', 'Bearer admin-token')
        .expect(200);
      assert.equal(inline.headers['content-type'], 'image/png');
      assert.match(inline.headers['content-disposition'], /^inline;/);

      const download = await request(app)
        .get('/api/v1/admin/support/inquiries/1/attachments/3?download=1')
        .set('Authorization', 'Bearer admin-token')
        .expect(200);
      assert.match(download.headers['content-disposition'], /^attachment;/);
    } finally {
      fs.rmSync(filePath, { force: true });
    }
  });

  test('unknown or mismatched support attachment returns 404', async () => {
    container.register('supportInquiryService', () => ({
      async getAdminAttachmentFile() {
        throw new AppError('Support inquiry attachment not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.FILE_NOT_FOUND,
        });
      },
    }));
    registerAuth('ADMIN');

    const res = await request(app)
      .get('/api/v1/admin/support/inquiries/1/attachments/999')
      .set('Authorization', 'Bearer admin-token')
      .expect(404);

    assert.equal(res.body.error_code, ERROR_CODES.FILE_NOT_FOUND);
  });

  test('admin can reply to support inquiry', async () => {
    registerAuth('ADMIN');

    const res = await request(app)
      .post('/api/v1/admin/support/inquiries/1/messages')
      .set('Authorization', 'Bearer admin-token')
      .send({ message: 'We will check this booking.' })
      .expect(201);

    assert.equal(res.body.data.status, 'IN_PROGRESS');
    assert.equal(res.body.data.messages[1].senderType, 'ADMIN');
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
        calls.push(['create', data.publicId, data.lookupTokenHash, data.message]);
        return 9;
      },
      async insertAttachment(_conn, data) {
        calls.push(['attachment', data.originalFileName, data.mimeType]);
        return 1;
      },
      async insertMessage(_conn, data) {
        calls.push(['message', data.senderType, data.message]);
        return 1;
      },
      async findById() {
        return {
          id: 9,
          public_id: 'SUP-260708-ABC123',
          lookup_token_hash: 'hash',
          status: 'NEW',
          created_at: '2026-07-08 12:00:00',
          messages: [],
          attachments: [],
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
    assert.equal(typeof result.lookupToken, 'string');
    assert.equal(result.attachmentCount, 1);
    assert.deepEqual(calls[0], 'begin');
    assert.equal(calls.some((call) => Array.isArray(call) && call[0] === 'attachment'), true);
    assert.equal(calls.some((call) => Array.isArray(call) && call[0] === 'message'), true);
  });

  test('public detail validates lookup token hash and returns messages', async () => {
    const service = new SupportInquiryService({}, {
      async findByPublicId() {
        const token = 'valid-token';
        return {
          id: 9,
          public_id: 'SUP-260708-ABC123',
          lookup_token_hash: service.hashLookupToken(token),
          status: 'NEW',
          messages: [{ id: 1, sender_type: 'ADMIN', message: 'Reply' }],
          attachments: [],
        };
      },
    });

    const result = await service.getPublicDetail('SUP-260708-ABC123', 'valid-token');
    assert.equal(result.messages[0].senderType, 'ADMIN');
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

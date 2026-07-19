process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const fs = require('fs');
const path = require('path');
const { test, describe, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const request = require('supertest');

const app = require('../src/app');
const container = require('../src/helpers/container');
const { uploadDir } = require('../src/config/multer');
const ERROR_CODES = require('../src/constants/errorCodes');
const PlatformSettingsService = require('../src/services/platformSettings.service');

function sign(role = 'ADMIN', id = 1) {
  return jwt.sign(
    { sub: id, email: `${role.toLowerCase()}@example.com`, role, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

class MemorySettingsRepository {
  constructor(initial = {}) {
    this.values = new Map(Object.entries(initial));
    this.upserts = [];
  }

  async findByGroup(groupName) {
    return [...this.values.entries()].map(([key_name, value]) => ({
      group_name: groupName,
      key_name,
      value,
      data_type: 'STRING',
    }));
  }

  async findByGroupAndKey(_groupName, keyName) {
    if (!this.values.has(keyName)) return null;
    return { value: this.values.get(keyName), data_type: 'STRING' };
  }

  async upsert(groupName, keyName, value, userId) {
    this.upserts.push({ groupName, keyName, value, userId });
    this.values.set(keyName, value);
  }
}

function serviceWith(initial = {}) {
  return new PlatformSettingsService(new MemorySettingsRepository(initial));
}

describe('PlatformSettingsService', () => {
  test('public settings include only customer-safe LINE fields', async () => {
    const settings = await serviceWith({
      lineQrDescription: 'LINE 문의 안내',
      lineQrImagePath: 'settings/line.png',
      bankName: 'SCB',
      accountName: 'T-Ride Ops',
      accountNumber: '1234567890',
      promptPayNumber: '0999999999',
      promptPayQrImagePath: 'settings/promptpay.png',
    }).getPublic();

    assert.deepEqual(Object.keys(settings).sort(), ['lineQrDescription', 'lineQrImageUrl']);
    assert.equal(settings.lineQrDescription, 'LINE 문의 안내');
    assert.equal(settings.lineQrImageUrl, '/api/v1/settings/assets/lineQr');
    assert.equal(settings.bankName, undefined);
    assert.equal(settings.accountNumber, undefined);
    assert.equal(settings.promptPayQrImageUrl, undefined);
  });

  test('admin settings retain settlement payment fields and image URLs', async () => {
    const settings = await serviceWith({
      lineQrDescription: 'LINE 문의 안내',
      lineQrImagePath: 'settings/line.png',
      bankName: 'SCB',
      accountName: 'T-Ride Ops',
      accountNumber: '1234567890',
      promptPayNumber: '0999999999',
      promptPayQrImagePath: 'settings/promptpay.png',
    }).getAdmin();

    assert.equal(settings.bankName, 'SCB');
    assert.equal(settings.accountName, 'T-Ride Ops');
    assert.equal(settings.accountNumber, '1234567890');
    assert.equal(settings.promptPayNumber, '0999999999');
    assert.equal(settings.lineQrImageUrl, '/api/v1/settings/assets/lineQr');
    assert.equal(settings.promptPayQrImageUrl, '/api/v1/settings/assets/promptPayQr');
  });

  test('line QR upload stores DB path and returns admin/public image URL', async () => {
    fs.mkdirSync(uploadDir, { recursive: true });
    const repository = new MemorySettingsRepository({ lineQrDescription: 'LINE 안내' });
    const service = new PlatformSettingsService(repository);
    const filePath = path.join(uploadDir, 'test-line-qr.png');
    fs.writeFileSync(filePath, Buffer.from([0x89, 0x50, 0x4e, 0x47]));

    const adminSettings = await service.saveImage('lineQr', {
      path: filePath,
      mimetype: 'image/png',
    }, 7);
    const publicSettings = await service.getPublic();

    assert.equal(repository.values.get('lineQrImagePath'), 'test-line-qr.png');
    assert.equal(adminSettings.lineQrImageUrl, '/api/v1/settings/assets/lineQr');
    assert.equal(publicSettings.lineQrImageUrl, '/api/v1/settings/assets/lineQr');
    assert.equal(adminSettings.promptPayQrImageUrl, null);
    fs.rmSync(filePath, { force: true });
  });

  test('PromptPay QR upload stores DB path for admin and driver settlement source', async () => {
    fs.mkdirSync(uploadDir, { recursive: true });
    const repository = new MemorySettingsRepository({ bankName: 'SCB' });
    const service = new PlatformSettingsService(repository);
    const filePath = path.join(uploadDir, 'test-promptpay-qr.jpg');
    fs.writeFileSync(filePath, Buffer.from([0xff, 0xd8, 0xff]));

    const adminSettings = await service.saveImage('promptPayQr', {
      path: filePath,
      mimetype: 'image/jpeg',
    }, 7);

    assert.equal(repository.values.get('promptPayQrImagePath'), 'test-promptpay-qr.jpg');
    assert.equal(adminSettings.promptPayQrImageUrl, '/api/v1/settings/assets/promptPayQr');
    fs.rmSync(filePath, { force: true });
  });

  test('invalid image kind or type does not update DB and removes partial file', async () => {
    fs.mkdirSync(uploadDir, { recursive: true });
    const repository = new MemorySettingsRepository({ lineQrImagePath: 'existing.png' });
    const service = new PlatformSettingsService(repository);
    const filePath = path.join(uploadDir, 'invalid-settings-upload.txt');
    fs.writeFileSync(filePath, 'not an image');

    await assert.rejects(
      () => service.saveImage('lineQr', { path: filePath, mimetype: 'text/plain' }, 7),
      (err) => err.errorCode === ERROR_CODES.INVALID_FILE_TYPE,
    );

    assert.equal(repository.values.get('lineQrImagePath'), 'existing.png');
    assert.equal(fs.existsSync(filePath), false);

    const secondPath = path.join(uploadDir, 'invalid-kind.png');
    fs.writeFileSync(secondPath, Buffer.from([0x89, 0x50]));
    await assert.rejects(
      () => service.saveImage('unknown', { path: secondPath, mimetype: 'image/png' }, 7),
      (err) => err.errorCode === ERROR_CODES.INVALID_FILE_TYPE,
    );
    assert.equal(repository.values.get('lineQrImagePath'), 'existing.png');
    assert.equal(fs.existsSync(secondPath), false);
  });

  test('DB failure does not leave a stale DB path or partial upload file', async () => {
    fs.mkdirSync(uploadDir, { recursive: true });
    const repository = new MemorySettingsRepository({ promptPayQrImagePath: 'existing.png' });
    repository.upsert = async () => {
      throw new Error('DB unavailable');
    };
    const service = new PlatformSettingsService(repository);
    const filePath = path.join(uploadDir, 'db-fail-settings-upload.png');
    fs.writeFileSync(filePath, Buffer.from([0x89, 0x50]));

    await assert.rejects(
      () => service.saveImage('promptPayQr', { path: filePath, mimetype: 'image/png' }, 7),
      /DB unavailable/,
    );

    assert.equal(repository.values.get('promptPayQrImagePath'), 'existing.png');
    assert.equal(fs.existsSync(filePath), false);
  });
});

describe('platform settings routes', () => {
  beforeEach(() => {
    container.register('platformSettingsService', () => ({
      async getPublic() {
        return { lineQrDescription: 'Public LINE', lineQrImageUrl: '/api/v1/settings/assets/lineQr' };
      },
      async getAdmin() {
        return {
          lineQrDescription: 'Public LINE',
          lineQrImageUrl: '/api/v1/settings/assets/lineQr',
          bankName: 'SCB',
          accountName: 'T-Ride Ops',
          accountNumber: '1234567890',
          promptPayNumber: '0999999999',
          promptPayQrImageUrl: '/api/v1/settings/assets/promptPayQr',
        };
      },
      async update() {
        throw new Error('not used');
      },
      async saveImage(kind, file) {
        return { kind, field: file?.fieldname, lineQrImageUrl: '/api/v1/settings/assets/lineQr' };
      },
    }));
  });

  test('public endpoint excludes settlement account details', async () => {
    const res = await request(app).get('/api/v1/settings/public').expect(200);

    assert.deepEqual(Object.keys(res.body.data).sort(), ['lineQrDescription', 'lineQrImageUrl']);
    assert.equal(JSON.stringify(res.body.data).includes('1234567890'), false);
  });

  test('admin endpoint keeps full settings payload', async () => {
    const res = await request(app)
      .get('/api/v1/admin/settings')
      .set('Authorization', `Bearer ${sign('ADMIN', 1)}`)
      .expect(200);

    assert.equal(res.body.data.bankName, 'SCB');
    assert.equal(res.body.data.accountNumber, '1234567890');
    assert.equal(res.body.data.promptPayQrImageUrl, '/api/v1/settings/assets/promptPayQr');
  });

  test('settings image upload requires admin auth and file field', async () => {
    await request(app)
      .post('/api/v1/admin/settings/images/lineQr')
      .attach('file', Buffer.from([0x89, 0x50]), { filename: 'line.png', contentType: 'image/png' })
      .expect(401);

    const res = await request(app)
      .post('/api/v1/admin/settings/images/lineQr')
      .set('Authorization', `Bearer ${sign('ADMIN', 1)}`)
      .attach('file', Buffer.from([0x89, 0x50]), { filename: 'line.png', contentType: 'image/png' })
      .expect(200);

    assert.equal(res.body.data.kind, 'lineQr');
    assert.equal(res.body.data.field, 'file');
  });
});

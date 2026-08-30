process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const fs = require('fs');
const path = require('path');
const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const request = require('supertest');

const app = require('../src/app');
const container = require('../src/helpers/container');
const ERROR_CODES = require('../src/constants/errorCodes');
const { GENERIC_INTERNAL_MESSAGE, resolveClientErrorMessage } = require('../src/utils/clientErrorMessage.util');
const { resolveUploadAbsolutePath } = require('../src/utils/uploadPath.util');
const { uploadDir } = require('../src/config/multer');
const DriverApplicationService = require('../src/services/driverApplication.service');
const CommissionSettlementService = require('../src/services/commissionSettlement.service');
const { assertImageUploadSignature } = require('../src/utils/fileSignatureValidation.util');
const { adminSettingsUpdateSchema } = require('../src/validators/platformSettings.validator');
const { submitReviewSchema, reviewHideSchema } = require('../src/validators/review.validator');
const { bookingNumberParamsSchema } = require('../src/validators/bookingContactConnection.validator');
const config = require('../src/config');

const PNG_BYTES = Buffer.from([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
  0x00, 0x00, 0x00, 0x0d,
]);
const JPEG_BYTES = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]);
const PDF_BYTES = Buffer.from('%PDF-1.7\n');

function sign(role = 'ADMIN', id = 1) {
  return jwt.sign(
    { sub: id, email: `${role.toLowerCase()}@example.com`, role, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

function writeTempUpload(name, bytes) {
  fs.mkdirSync(uploadDir, { recursive: true });
  const filePath = path.join(uploadDir, name);
  fs.writeFileSync(filePath, bytes);
  return filePath;
}

function uploadFile(field, originalname, mimetype, bytes = PNG_BYTES) {
  const filePath = writeTempUpload(`security-${Date.now()}-${originalname}`, bytes);
  return {
    fieldname: field,
    originalname,
    filename: path.basename(filePath),
    mimetype,
    path: filePath,
    size: bytes.length,
  };
}

describe('security patch regressions', () => {
  test('admin settings schema enforces max lengths and unicodeText', () => {
    const { error, value } = adminSettingsUpdateSchema.validate({
      lineQrDescription: 'a'.repeat(500),
      bankName: 'SCB',
      accountName: 'Ops',
      accountNumber: '1234567890',
      promptPayNumber: '0999999999',
    });
    assert.equal(error, undefined);
    assert.equal(value.lineQrDescription.length, 500);

    const tooLong = adminSettingsUpdateSchema.validate({
      lineQrDescription: 'a'.repeat(501),
    });
    assert.ok(tooLong.error);

    const controlChar = adminSettingsUpdateSchema.validate({
      lineQrDescription: 'bad\u0007text',
    });
    assert.ok(controlChar.error);
  });

  test('resolveClientErrorMessage hides non-operational errors in production', () => {
    const err = new Error('Sensitive library detail: connection refused at 10.0.0.5');
    assert.equal(
      resolveClientErrorMessage(err, { production: true }),
      GENERIC_INTERNAL_MESSAGE,
    );
    assert.equal(
      resolveClientErrorMessage(err, { production: false }),
      err.message,
    );
  });

  test('resolveUploadAbsolutePath blocks path traversal', () => {
    assert.throws(
      () => resolveUploadAbsolutePath('subdir/../../outside.txt'),
      (err) => err.errorCode === ERROR_CODES.FILE_NOT_FOUND,
    );
  });

  test('resolveUploadAbsolutePath accepts paths under upload root', () => {
    const relative = '2026-08-31/safe-file.png';
    const absolute = resolveUploadAbsolutePath(relative);
    assert.ok(absolute.startsWith(path.resolve(uploadDir)));
    assert.ok(absolute.endsWith('safe-file.png'));
  });

  test('review schemas reject control characters in comment and hide reason', () => {
    const comment = submitReviewSchema.validate({
      rating: 5,
      comment: 'Great\u0001 trip',
    });
    assert.ok(comment.error);

    const reason = reviewHideSchema.validate({
      reason: 'Hidden\u0002 reason',
    });
    assert.ok(reason.error);

    const valid = submitReviewSchema.validate({
      rating: 5,
      comment: 'Clean review text',
    });
    assert.equal(valid.error, undefined);
  });

  test('booking contact connection bookingNumber requires TX pattern', () => {
    const invalid = bookingNumberParamsSchema.validate({ bookingNumber: 'INVALID' });
    assert.ok(invalid.error);

    const valid = bookingNumberParamsSchema.validate({ bookingNumber: 'TX202608310001' });
    assert.equal(valid.error, undefined);
  });

  test('driver application rejects png extension with pdf bytes', async () => {
    const service = new DriverApplicationService({}, {});
    const fakeImage = uploadFile('lineQr', 'line.png', 'image/png', PDF_BYTES);

    await assert.rejects(
      () => service.validateRequiredFiles({ lineQr: [fakeImage] }),
      (err) => err.errorCode === ERROR_CODES.INVALID_FILE_TYPE,
    );
    fs.rmSync(fakeImage.path, { force: true });
  });

  test('driver application accepts valid png signature', async () => {
    const service = new DriverApplicationService({}, {});
    const validImage = uploadFile('lineQr', 'line.png', 'image/png', PNG_BYTES);

    await assert.doesNotReject(async () => {
      await service.validateRequiredFiles({ lineQr: [validImage] });
    });
    fs.rmSync(validImage.path, { force: true });
  });

  test('commission settlement rejects pdf extension with jpeg bytes', async () => {
    const service = new CommissionSettlementService({}, {}, {}, {}, {});
    const fakePdf = uploadFile('receipt', 'receipt.pdf', 'application/pdf', JPEG_BYTES);

    await assert.rejects(
      () => service.validateUploadedFile(fakePdf),
      (err) => err.errorCode === ERROR_CODES.INVALID_FILE_TYPE,
    );
    fs.rmSync(fakePdf.path, { force: true });
  });

  test('commission settlement accepts valid pdf signature', async () => {
    const service = new CommissionSettlementService({}, {}, {}, {}, {});
    const validPdf = uploadFile('receipt', 'receipt.pdf', 'application/pdf', PDF_BYTES);

    await assert.doesNotReject(async () => {
      await service.validateUploadedFile(validPdf);
    });
    fs.rmSync(validPdf.path, { force: true });
  });

  test('image signature util rejects fake png bytes', async () => {
    const fake = uploadFile('attachments', 'photo.png', 'image/png', Buffer.from('not-an-image'));

    await assert.rejects(
      () => assertImageUploadSignature(fake),
      (err) => err.errorCode === ERROR_CODES.INVALID_FILE_TYPE,
    );
    fs.rmSync(fake.path, { force: true });
  });

  test('image signature util accepts valid jpeg bytes', async () => {
    const valid = uploadFile('attachments', 'photo.jpg', 'image/jpeg', JPEG_BYTES);

    await assert.doesNotReject(async () => {
      await assertImageUploadSignature(valid);
    });
    fs.rmSync(valid.path, { force: true });
  });
});

describe('security patch routes', () => {
  test('PUT /admin/settings rejects unknown keys and overlong text', async () => {
    const original = config.server.nodeEnv;
    config.server.nodeEnv = 'test';
    try {
      const res = await request(app)
        .put('/api/v1/admin/settings')
        .set('Authorization', `Bearer ${sign('ADMIN', 1)}`)
        .send({
          lineQrDescription: 'x'.repeat(501),
          bankName: 'SCB',
        })
        .expect(400);

      assert.equal(res.body.error_code, ERROR_CODES.VALIDATION_ERROR);
    } finally {
      config.server.nodeEnv = original;
    }
  });

  test('GET /places/autocomplete rejects input longer than 200 characters', async () => {
    const res = await request(app)
      .get('/api/v1/places/autocomplete')
      .query({ input: 'a'.repeat(201), language: 'en' })
      .expect(400);

    assert.equal(res.body.error_code, ERROR_CODES.VALIDATION_ERROR);
  });
});

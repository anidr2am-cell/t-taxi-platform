const test = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = 'test';
process.env.DB_USER = 'test';
process.env.DB_NAME = 'tride_test';
process.env.JWT_ACCESS_SECRET = 'test-access-secret';
process.env.JWT_REFRESH_SECRET = 'test-refresh-secret';

const ERROR_CODES = require('../src/constants/errorCodes');
const PlatformSettingsService = require('../src/services/platformSettings.service');

test('updateContactChannels rejects unsafe messenger URLs', () => {
  const service = new PlatformSettingsService({
    async upsert() {},
    async findByGroup() {
      return [];
    },
  });

  assert.throws(
    () => service.validateContactChannelUrls({
      contactLineAddUrl: 'javascript:alert(1)',
    }),
    (err) => err.errorCode === ERROR_CODES.VALIDATION_ERROR,
  );
});

test('updateContactChannels accepts https messenger URLs', () => {
  const service = new PlatformSettingsService({
    async upsert() {},
    async findByGroup() {
      return [];
    },
  });

  assert.doesNotThrow(() => service.validateContactChannelUrls({
    contactLineAddUrl: 'https://line.me/R/ti/p/@example',
    contactKakaoAddUrl: 'https://open.kakao.com/o/s/example',
  }));
});

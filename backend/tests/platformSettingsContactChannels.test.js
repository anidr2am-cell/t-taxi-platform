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

test('updateContactChannels allows empty messenger URLs', () => {
  const service = new PlatformSettingsService({
    async upsert() {},
    async findByGroup() {
      return [];
    },
  });

  assert.doesNotThrow(() => service.validateContactChannelUrls({
    contactLineAddUrl: '',
    contactKakaoAddUrl: '',
  }));
});

test('getContactChannelsAdmin returns guest lookup banner fields with defaults', async () => {
  const service = new PlatformSettingsService({
    async findByGroup(groupName) {
      if (groupName !== 'contact_channels') return [];
      return [
        { key_name: 'guestLookupInquiryBannerEnabled', value: 'true' },
        { key_name: 'guestLookupInquiryBannerMessage', value: '문의해 주세요' },
        { key_name: 'contactKakaoAddUrl', value: 'https://open.kakao.com/o/s/example' },
        { key_name: 'contactLineAddUrl', value: 'https://line.me/R/ti/p/@example' },
      ];
    },
    async upsert() {},
  });

  const settings = await service.getContactChannelsAdmin();

  assert.equal(settings.guestLookupInquiryBannerEnabled, true);
  assert.equal(settings.guestLookupInquiryBannerMessage, '문의해 주세요');
  assert.equal(settings.contactKakaoAddUrl, 'https://open.kakao.com/o/s/example');
  assert.equal(settings.contactLineAddUrl, 'https://line.me/R/ti/p/@example');
  assert.equal(settings.contactLineEnabled, false);
});

test('updateContactChannels persists guest lookup banner settings', async () => {
  const upserts = [];
  const service = new PlatformSettingsService({
    async findByGroup(groupName) {
      if (groupName !== 'contact_channels') return [];
      return upserts.map(({ keyName, value }) => ({
        key_name: keyName,
        value,
      }));
    },
    async upsert(_groupName, keyName, value) {
      upserts.push({ keyName, value });
    },
  });

  const result = await service.updateContactChannels({
    guestLookupInquiryBannerEnabled: true,
    guestLookupInquiryBannerMessage: '실시간 문의',
    contactKakaoAddUrl: '',
    contactLineAddUrl: '',
  }, 9);

  assert.equal(result.guestLookupInquiryBannerEnabled, true);
  assert.equal(result.guestLookupInquiryBannerMessage, '실시간 문의');
  assert.equal(
    upserts.find((row) => row.keyName === 'guestLookupInquiryBannerEnabled')?.value,
    'true',
  );
  assert.equal(
    upserts.find((row) => row.keyName === 'contactKakaoAddUrl')?.value,
    '',
  );
});

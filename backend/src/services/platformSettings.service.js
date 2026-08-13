const fs = require('fs/promises');
const path = require('path');
const { uploadDir } = require('../config/multer');
const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const { settingsAssetUrl } = require('../utils/settingsAssetUrl');
const {
  detectImageFileSignature,
  isSupportedSettingsImageMetadata,
} = require('../utils/imageSignature');
const { validateContactChannelUrl } = require('../utils/contactChannelUrl.util');

const GROUP = 'operations';
const CONTACT_GROUP = 'contact_channels';
const TEXT_KEYS = ['lineQrDescription', 'bankName', 'accountName', 'accountNumber', 'promptPayNumber'];
const CONTACT_TEXT_KEYS = [
  'contactLineEnabled', 'contactLineDisplayName', 'contactLineAddUrl', 'contactLineAccountId',
  'contactKakaoEnabled', 'contactKakaoDisplayName', 'contactKakaoAddUrl', 'contactKakaoAccountId',
  'contactWhatsappEnabled', 'contactWhatsappDisplayName', 'contactWhatsappPhoneNumber',
  'contactWechatEnabled', 'contactWechatDisplayName', 'contactWechatAccountId',
];
const IMAGE_KEYS = {
  lineQr: 'lineQrImagePath',
  promptPayQr: 'promptPayQrImagePath',
  contactLineQr: 'contactLineQrImagePath',
  contactKakaoQr: 'contactKakaoQrImagePath',
  contactWechatQr: 'contactWechatQrImagePath',
};

class PlatformSettingsService {
  constructor(settingsRepository) {
    this.settingsRepository = settingsRepository;
  }

  async get() {
    return this.getAdmin();
  }

  async getAdmin() {
    const rows = await this.settingsRepository.findByGroup(GROUP);
    const values = Object.fromEntries(rows.map((row) => [row.key_name, row.value]));
    return {
      lineQrDescription: values.lineQrDescription || '',
      bankName: values.bankName || '',
      accountName: values.accountName || '',
      accountNumber: values.accountNumber || '',
      promptPayNumber: values.promptPayNumber || '',
      lineQrImageUrl: settingsAssetUrl('lineQr', values.lineQrImagePath),
      promptPayQrImageUrl: settingsAssetUrl('promptPayQr', values.promptPayQrImagePath),
    };
  }

  async getPublic() {
    const rows = await this.settingsRepository.findByGroup(GROUP);
    const values = Object.fromEntries(rows.map((row) => [row.key_name, row.value]));
    return {
      lineQrDescription: values.lineQrDescription || '',
      lineQrImageUrl: settingsAssetUrl('lineQr', values.lineQrImagePath),
      contactChannels: await this.buildContactChannelsPublic(values),
    };
  }

  async getContactChannelsPublic() {
    const rows = await this.settingsRepository.findByGroup(GROUP);
    const contactRows = await this.settingsRepository.findByGroup(CONTACT_GROUP);
    const values = {
      ...Object.fromEntries(rows.map((row) => [row.key_name, row.value])),
      ...Object.fromEntries(contactRows.map((row) => [row.key_name, row.value])),
    };
    return { channels: await this.buildContactChannelsPublic(values) };
  }

  truthy(value) {
    return String(value ?? '').trim().toLowerCase() === 'true' || value === '1';
  }

  async buildContactChannelsPublic(values = {}) {
    const channels = [
      {
        code: 'LINE',
        enabled: this.truthy(values.contactLineEnabled),
        displayName: values.contactLineDisplayName || 'LINE',
        addUrl: values.contactLineAddUrl || '',
        accountId: values.contactLineAccountId || '',
        qrImageUrl: settingsAssetUrl('contactLineQr', values.contactLineQrImagePath),
      },
      {
        code: 'KAKAO',
        enabled: this.truthy(values.contactKakaoEnabled),
        displayName: values.contactKakaoDisplayName || 'KakaoTalk',
        addUrl: values.contactKakaoAddUrl || '',
        accountId: values.contactKakaoAccountId || '',
        qrImageUrl: settingsAssetUrl('contactKakaoQr', values.contactKakaoQrImagePath),
      },
      {
        code: 'WHATSAPP',
        enabled: this.truthy(values.contactWhatsappEnabled),
        displayName: values.contactWhatsappDisplayName || 'WhatsApp',
        phoneNumber: values.contactWhatsappPhoneNumber || '',
      },
      {
        code: 'WECHAT',
        enabled: this.truthy(values.contactWechatEnabled),
        displayName: values.contactWechatDisplayName || 'WeChat',
        accountId: values.contactWechatAccountId || '',
        qrImageUrl: settingsAssetUrl('contactWechatQr', values.contactWechatQrImagePath),
      },
    ];
    return channels.filter((channel) => channel.enabled);
  }

  async updateContactChannels(input, userId) {
    this.validateContactChannelUrls(input);
    await Promise.all(CONTACT_TEXT_KEYS.map((key) => this.settingsRepository.upsert(
      CONTACT_GROUP, key, String(input[key] ?? '').trim(), userId,
    )));
    return this.getContactChannelsPublic();
  }

  validateContactChannelUrls(input = {}) {
    const urlFields = [
      { key: 'contactLineAddUrl', label: 'LINE add URL' },
      { key: 'contactKakaoAddUrl', label: 'Kakao add URL' },
    ];
    for (const field of urlFields) {
      const raw = String(input[field.key] ?? '').trim();
      if (!raw) continue;
      const result = validateContactChannelUrl(raw);
      if (!result.valid) {
        throw new AppError(`${field.label} is invalid`, {
          statusCode: HTTP_STATUS.BAD_REQUEST,
          errorCode: ERROR_CODES.VALIDATION_ERROR,
          errors: [{ field: field.key, message: result.reason }],
        });
      }
    }
  }

  async update(input, userId) {
    await Promise.all(TEXT_KEYS.map((key) => this.settingsRepository.upsert(
      GROUP, key, String(input[key] ?? '').trim(), userId,
    )));
    return this.getAdmin();
  }

  async saveImage(kind, file, userId) {
    const key = IMAGE_KEYS[kind];
    if (!key || !file) {
      await this.cleanupUploadedFile(file);
      throw this.invalidImage();
    }
    let detectedType = null;
    try {
      detectedType = await detectImageFileSignature(file.path);
    } catch (_) {
      await this.cleanupUploadedFile(file);
      throw this.invalidImage();
    }
    if (!isSupportedSettingsImageMetadata(file, detectedType)) {
      await this.cleanupUploadedFile(file);
      throw this.invalidImage();
    }
    const relativePath = path.relative(uploadDir, file.path).replace(/\\/g, '/');
    try {
      await this.settingsRepository.upsert(GROUP, key, relativePath, userId);
      return this.getAdmin();
    } catch (err) {
      await this.cleanupUploadedFile(file);
      throw err;
    }
  }

  async getImage(kind) {
    const key = IMAGE_KEYS[kind];
    if (!key) throw this.notFound();
    const row = await this.settingsRepository.findByGroupAndKey(GROUP, key);
    if (!row?.value) throw this.notFound();
    const absolutePath = path.resolve(uploadDir, row.value);
    const root = `${path.resolve(uploadDir)}${path.sep}`;
    if (!absolutePath.startsWith(root)) throw this.notFound();
    try {
      await fs.access(absolutePath);
    } catch (_) {
      throw this.notFound();
    }
    return absolutePath;
  }

  async cleanupUploadedFile(file) {
    if (!file?.path) return;
    try {
      await fs.rm(file.path, { force: true });
    } catch (_) {
      // Best-effort cleanup only. The original validation or DB error is more important.
    }
  }

  notFound() {
    return new AppError('Settings image not found', {
      statusCode: HTTP_STATUS.NOT_FOUND,
      errorCode: ERROR_CODES.FILE_NOT_FOUND,
    });
  }

  invalidImage() {
    return new AppError('Only PNG and JPEG images are supported', {
      statusCode: HTTP_STATUS.BAD_REQUEST,
      errorCode: ERROR_CODES.INVALID_SETTINGS_IMAGE,
    });
  }
}

module.exports = PlatformSettingsService;

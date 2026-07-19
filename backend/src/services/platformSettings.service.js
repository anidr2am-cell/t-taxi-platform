const fs = require('fs/promises');
const path = require('path');
const { uploadDir } = require('../config/multer');
const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const { settingsAssetUrl } = require('../utils/settingsAssetUrl');

const GROUP = 'operations';
const TEXT_KEYS = ['lineQrDescription', 'bankName', 'accountName', 'accountNumber', 'promptPayNumber'];
const IMAGE_KEYS = { lineQr: 'lineQrImagePath', promptPayQr: 'promptPayQrImagePath' };

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
    };
  }

  async update(input, userId) {
    await Promise.all(TEXT_KEYS.map((key) => this.settingsRepository.upsert(
      GROUP, key, String(input[key] ?? '').trim(), userId,
    )));
    return this.getAdmin();
  }

  async saveImage(kind, file, userId) {
    const key = IMAGE_KEYS[kind];
    if (!key || !file || !String(file.mimetype || '').startsWith('image/')) {
      await this.cleanupUploadedFile(file);
      throw new AppError('Invalid settings image', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.INVALID_FILE_TYPE,
      });
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
}

module.exports = PlatformSettingsService;

const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const { formatServiceDateTimeForApi } = require('../utils/serviceDateTime.util');
const {
  adminHomeBannerImageUrl,
  publicHomeBannerImageUrl,
} = require('../utils/homeBannerAssetUrl');
const {
  saveSettingsImage,
  resolveUploadAbsolutePath,
  deleteStoredImage,
} = require('../utils/saveSettingsImage');

class HomeBannerService {
  constructor(homeBannerRepository) {
    this.homeBannerRepository = homeBannerRepository;
  }

  mapAdminRow(row) {
    return {
      id: Number(row.id),
      displayOrder: Number(row.display_order),
      isActive: Boolean(row.is_active),
      imageUrl: adminHomeBannerImageUrl(row.id),
      createdAt: formatServiceDateTimeForApi(row.created_at),
      updatedAt: formatServiceDateTimeForApi(row.updated_at),
    };
  }

  mapPublicRow(row) {
    return {
      id: Number(row.id),
      displayOrder: Number(row.display_order),
      imageUrl: publicHomeBannerImageUrl(row.id),
    };
  }

  notFound() {
    return new AppError('Home banner not found', {
      statusCode: HTTP_STATUS.NOT_FOUND,
      errorCode: ERROR_CODES.HOME_BANNER_NOT_FOUND,
    });
  }

  async createBanner({ file, displayOrder = null, createdByAdminId = null }) {
    const imagePath = await saveSettingsImage(file);
    let resolvedOrder = displayOrder;
    if (resolvedOrder == null || !Number.isFinite(Number(resolvedOrder))) {
      const maxOrder = await this.homeBannerRepository.getMaxDisplayOrder();
      resolvedOrder = maxOrder + 1;
    }
    const bannerId = await this.homeBannerRepository.insertBanner({
      imagePath,
      displayOrder: Number(resolvedOrder),
      createdByAdminId,
    });
    const banner = await this.homeBannerRepository.findById(bannerId);
    return this.mapAdminRow(banner);
  }

  async listAdminBanners() {
    const rows = await this.homeBannerRepository.listAll();
    return rows.map((row) => this.mapAdminRow(row));
  }

  async listPublicBanners() {
    const rows = await this.homeBannerRepository.listActive();
    return rows.map((row) => this.mapPublicRow(row));
  }

  async updateBanner(bannerId, { isActive, displayOrder }) {
    const banner = await this.homeBannerRepository.findById(bannerId);
    if (!banner) throw this.notFound();

    const affected = await this.homeBannerRepository.updateBanner(bannerId, {
      isActive,
      displayOrder,
    });
    if (affected === 0) throw this.notFound();

    const updated = await this.homeBannerRepository.findById(bannerId);
    return this.mapAdminRow(updated);
  }

  async deleteBanner(bannerId) {
    const banner = await this.homeBannerRepository.findById(bannerId);
    if (!banner) throw this.notFound();

    const affected = await this.homeBannerRepository.deleteById(bannerId);
    if (affected === 0) throw this.notFound();

    await deleteStoredImage(banner.image_path);
    return true;
  }

  async getAdminImagePath(bannerId) {
    const banner = await this.homeBannerRepository.findById(bannerId);
    if (!banner?.image_path) throw this.notFound();
    return resolveUploadAbsolutePath(banner.image_path);
  }

  async getPublicImagePath(bannerId) {
    const banner = await this.homeBannerRepository.findById(bannerId);
    if (!banner || !banner.is_active || !banner.image_path) throw this.notFound();
    return resolveUploadAbsolutePath(banner.image_path);
  }
}

module.exports = HomeBannerService;

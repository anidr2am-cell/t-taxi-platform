const express = require('express');
const homeBannerController = require('../controllers/homeBanner.controller');
const validate = require('../middlewares/validate.middleware');
const { authMiddleware } = require('../middlewares/auth.middleware');
const roleMiddleware = require('../middlewares/role.middleware');
const ROLES = require('../constants/roles');
const { upload } = require('../config/multer');
const {
  bannerIdParamSchema,
  createHomeBannerSchema,
  updateHomeBannerSchema,
} = require('../validators/homeBanner.validator');

const router = express.Router();
const adminOnly = [authMiddleware, roleMiddleware([ROLES.ADMIN, ROLES.SUPER_ADMIN])];

router.get(
  '/home-banners',
  adminOnly,
  homeBannerController.listAdminBanners,
);

router.post(
  '/home-banners',
  adminOnly,
  upload.single('file'),
  homeBannerController.handleUploadError,
  validate({ body: createHomeBannerSchema }),
  homeBannerController.createBanner,
);

router.patch(
  '/home-banners/:id',
  adminOnly,
  validate({
    params: bannerIdParamSchema,
    body: updateHomeBannerSchema,
  }),
  homeBannerController.updateBanner,
);

router.delete(
  '/home-banners/:id',
  adminOnly,
  validate({ params: bannerIdParamSchema }),
  homeBannerController.deleteBanner,
);

router.get(
  '/home-banners/:id/image',
  adminOnly,
  validate({ params: bannerIdParamSchema }),
  homeBannerController.streamAdminBannerImage,
);

module.exports = router;

const express = require('express');
const couponController = require('../controllers/coupon.controller');
const validate = require('../middlewares/validate.middleware');
const { authMiddleware } = require('../middlewares/auth.middleware');
const roleMiddleware = require('../middlewares/role.middleware');
const ROLES = require('../constants/roles');
const { upload } = require('../config/multer');
const {
  customerSearchQuerySchema,
  recentCustomersQuerySchema,
  issueCouponSchema,
  couponIdParamSchema,
  adminCouponListQuerySchema,
  createTemplateSchema,
  updateTemplateSchema,
} = require('../validators/coupon.validator');

const router = express.Router();
const adminOnly = [authMiddleware, roleMiddleware([ROLES.ADMIN, ROLES.SUPER_ADMIN])];

router.get(
  '/customers/search',
  adminOnly,
  validate({ query: customerSearchQuerySchema }),
  couponController.searchCustomers,
);

router.get(
  '/customers/recent',
  adminOnly,
  validate({ query: recentCustomersQuerySchema }),
  couponController.listRecentCustomers,
);

router.get(
  '/coupon-templates',
  adminOnly,
  couponController.listTemplates,
);

router.post(
  '/coupon-templates',
  adminOnly,
  upload.single('file'),
  couponController.handleUploadError,
  validate({ body: createTemplateSchema }),
  couponController.createTemplate,
);

router.patch(
  '/coupon-templates/:id',
  adminOnly,
  validate({
    params: couponIdParamSchema,
    body: updateTemplateSchema,
  }),
  couponController.updateTemplate,
);

router.get(
  '/coupon-templates/:id/image',
  adminOnly,
  validate({ params: couponIdParamSchema }),
  couponController.streamTemplateImage,
);

router.get(
  '/coupons',
  adminOnly,
  validate({ query: adminCouponListQuerySchema }),
  couponController.listRecentCoupons,
);

router.post(
  '/coupons',
  adminOnly,
  validate({ body: issueCouponSchema }),
  couponController.issueCoupon,
);

router.delete(
  '/coupons/:id',
  adminOnly,
  validate({ params: couponIdParamSchema }),
  couponController.cancelCoupon,
);

module.exports = router;

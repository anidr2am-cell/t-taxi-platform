const express = require('express');
const couponController = require('../controllers/coupon.controller');
const validate = require('../middlewares/validate.middleware');
const { authMiddleware } = require('../middlewares/auth.middleware');
const roleMiddleware = require('../middlewares/role.middleware');
const ROLES = require('../constants/roles');
const {
  customerSearchQuerySchema,
  issueCouponSchema,
  couponIdParamSchema,
  adminCouponListQuerySchema,
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

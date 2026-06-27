const express = require('express');
const reviewController = require('../controllers/review.controller');
const validate = require('../middlewares/validate.middleware');
const { authMiddleware } = require('../middlewares/auth.middleware');
const roleMiddleware = require('../middlewares/role.middleware');
const ROLES = require('../constants/roles');
const {
  reviewIdParamsSchema,
  adminReviewListQuerySchema,
  reviewHideSchema,
} = require('../validators/review.validator');

const router = express.Router();
const adminOnly = [authMiddleware, roleMiddleware([ROLES.ADMIN, ROLES.SUPER_ADMIN])];

router.get(
  '/reviews',
  adminOnly,
  validate({ query: adminReviewListQuerySchema }),
  reviewController.listAdminReviews,
);

router.get(
  '/reviews/:reviewId',
  adminOnly,
  validate({ params: reviewIdParamsSchema }),
  reviewController.getAdminReview,
);

router.post(
  '/reviews/:reviewId/hide',
  adminOnly,
  validate({ params: reviewIdParamsSchema, body: reviewHideSchema }),
  reviewController.hideAdminReview,
);

router.post(
  '/reviews/:reviewId/restore',
  adminOnly,
  validate({ params: reviewIdParamsSchema }),
  reviewController.restoreAdminReview,
);

module.exports = router;

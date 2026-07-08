const express = require('express');
const supportInquiryController = require('../controllers/supportInquiry.controller');
const validate = require('../middlewares/validate.middleware');
const { authMiddleware } = require('../middlewares/auth.middleware');
const roleMiddleware = require('../middlewares/role.middleware');
const ROLES = require('../constants/roles');
const {
  adminSupportInquiryListQuerySchema,
  adminSupportInquiryIdParamsSchema,
  adminSupportInquiryStatusSchema,
} = require('../validators/supportInquiry.validator');

const router = express.Router();
const adminOnly = [authMiddleware, roleMiddleware([ROLES.ADMIN, ROLES.SUPER_ADMIN])];

router.get(
  '/support/inquiries',
  adminOnly,
  validate({ query: adminSupportInquiryListQuerySchema }),
  supportInquiryController.listAdmin,
);

router.get(
  '/support/inquiries/:id',
  adminOnly,
  validate({ params: adminSupportInquiryIdParamsSchema }),
  supportInquiryController.getAdminDetail,
);

router.patch(
  '/support/inquiries/:id/status',
  adminOnly,
  validate({
    params: adminSupportInquiryIdParamsSchema,
    body: adminSupportInquiryStatusSchema,
  }),
  supportInquiryController.updateAdminStatus,
);

module.exports = router;

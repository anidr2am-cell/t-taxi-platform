const express = require('express');
const supportInquiryController = require('../controllers/supportInquiry.controller');
const { upload } = require('../config/multer');
const validate = require('../middlewares/validate.middleware');
const createRateLimit = require('../middlewares/rateLimit.middleware');
const { createSupportInquirySchema } = require('../validators/supportInquiry.validator');

const router = express.Router();
const publicLimiter = createRateLimit({ windowMs: 60_000, max: 30 });
const attachments = upload.array('attachments', 5);

router.post(
  '/inquiries',
  publicLimiter,
  attachments,
  supportInquiryController.handleUploadError,
  supportInquiryController.normalizeMultipartBody,
  validate({ body: createSupportInquirySchema }),
  supportInquiryController.create,
);

module.exports = router;

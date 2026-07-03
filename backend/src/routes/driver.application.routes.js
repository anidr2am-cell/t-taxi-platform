const express = require('express');
const driverApplicationController = require('../controllers/driverApplication.controller');
const { upload } = require('../config/multer');
const validate = require('../middlewares/validate.middleware');
const createRateLimit = require('../middlewares/rateLimit.middleware');
const {
  driverApplicationCreateSchema,
  driverApplicationStatusQuerySchema,
  driverApplicationResubmitParamsSchema,
  driverApplicationResubmitSchema,
} = require('../validators/driverApplication.validator');

const router = express.Router();
const publicLimiter = createRateLimit({ windowMs: 60_000, max: 30 });
const applicationFiles = upload.fields([
  { name: 'lineQr', maxCount: 1 },
  { name: 'vehiclePhotos', maxCount: 6 },
  { name: 'insuranceCertificate', maxCount: 1 },
  { name: 'vehicleRegistration', maxCount: 1 },
  { name: 'taxCertificate', maxCount: 1 },
]);

router.post(
  '/',
  publicLimiter,
  applicationFiles,
  driverApplicationController.normalizeMultipartBody,
  validate({ body: driverApplicationCreateSchema }),
  driverApplicationController.submit,
);

router.get(
  '/status',
  publicLimiter,
  validate({ query: driverApplicationStatusQuerySchema }),
  driverApplicationController.status,
);

router.post(
  '/:applicationNumber/resubmit',
  publicLimiter,
  applicationFiles,
  driverApplicationController.normalizeMultipartBody,
  validate({
    params: driverApplicationResubmitParamsSchema,
    body: driverApplicationResubmitSchema,
  }),
  driverApplicationController.resubmit,
);

module.exports = router;

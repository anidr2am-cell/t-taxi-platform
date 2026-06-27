const express = require('express');
const settlementController = require('../controllers/settlement.controller');
const validate = require('../middlewares/validate.middleware');
const { single } = require('../config/multer');
const {
  bookingNumberParamsSchema,
} = require('../validators/settlement.validator');

const router = express.Router();

router.get('/', settlementController.listDriverSettlements);
router.get(
  '/:bookingNumber',
  validate({ params: bookingNumberParamsSchema }),
  settlementController.getDriverSettlement,
);
router.post(
  '/:bookingNumber/receipt',
  validate({ params: bookingNumberParamsSchema }),
  single,
  settlementController.handleUploadError,
  settlementController.uploadDriverReceipt,
);
router.get(
  '/:bookingNumber/receipt',
  validate({ params: bookingNumberParamsSchema }),
  settlementController.getDriverReceipt,
);

module.exports = router;

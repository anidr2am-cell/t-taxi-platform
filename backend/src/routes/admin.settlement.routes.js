const express = require('express');
const settlementController = require('../controllers/settlement.controller');
const validate = require('../middlewares/validate.middleware');
const { authMiddleware } = require('../middlewares/auth.middleware');
const roleMiddleware = require('../middlewares/role.middleware');
const ROLES = require('../constants/roles');
const {
  bookingNumberParamsSchema,
  adminSettlementListQuerySchema,
  settlementManualApproveSchema,
  settlementRejectSchema,
} = require('../validators/settlement.validator');

const router = express.Router();
const adminOnly = [authMiddleware, roleMiddleware([ROLES.ADMIN, ROLES.SUPER_ADMIN])];

router.get(
  '/settlements',
  adminOnly,
  validate({ query: adminSettlementListQuerySchema }),
  settlementController.listAdminSettlements,
);

router.get(
  '/settlements/:bookingNumber',
  adminOnly,
  validate({ params: bookingNumberParamsSchema }),
  settlementController.getAdminSettlement,
);

router.post(
  '/settlements/:bookingNumber/approve',
  adminOnly,
  validate({ params: bookingNumberParamsSchema }),
  settlementController.approveSettlement,
);

router.post(
  '/settlements/:bookingNumber/manual-approve',
  adminOnly,
  validate({ params: bookingNumberParamsSchema, body: settlementManualApproveSchema }),
  settlementController.manualApproveSettlement,
);

router.post(
  '/settlements/:bookingNumber/reject',
  adminOnly,
  validate({ params: bookingNumberParamsSchema, body: settlementRejectSchema }),
  settlementController.rejectSettlement,
);

router.get(
  '/settlements/:bookingNumber/receipt',
  adminOnly,
  validate({ params: bookingNumberParamsSchema }),
  settlementController.getAdminReceipt,
);

module.exports = router;

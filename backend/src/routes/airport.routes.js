const express = require('express');
const router = express.Router();

const asyncHandler = require('../utils/asyncHandler');
const { success } = require('../utils/apiResponse');
const RegionRepository = require('../repositories/pricingRegion.repository');
router.get('/', asyncHandler(async (_req, res) => {
  const regions = await new RegionRepository().list();
  return success(res, regions.filter(r => r.is_active && r.airport_iata).map(r => ({ code: r.airport_iata })));
}));

module.exports = router;

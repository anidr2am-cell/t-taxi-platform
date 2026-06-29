const asyncHandler = require('../utils/asyncHandler');
const { success } = require('../utils/apiResponse');
const container = require('../helpers/container');

const getAdminDashboardService = () => container.get('adminDashboardService');

const getMetrics = asyncHandler(async (_req, res) => {
  const data = await getAdminDashboardService().getMetrics();
  return success(res, data);
});

module.exports = {
  getMetrics,
};

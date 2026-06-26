const asyncHandler = require('../utils/asyncHandler');
const { success } = require('../utils/apiResponse');
const container = require('../helpers/container');

const getVehicleRecommendationService = () => container.get('vehicleRecommendationService');

const recommendVehicle = asyncHandler(async (req, res) => {
  const data = await getVehicleRecommendationService().recommend(req.body);
  return success(res, data, data.message);
});

module.exports = {
  recommendVehicle,
};

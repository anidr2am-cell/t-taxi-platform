const asyncHandler = require('../utils/asyncHandler');
const { success } = require('../utils/apiResponse');
const container = require('../helpers/container');

const getVehicleService = () => container.get('vehicleService');

const listTypes = asyncHandler(async (req, res) => {
  const data = await getVehicleService().listTypes();
  return success(res, data, 'OK');
});

module.exports = {
  listTypes,
};

const asyncHandler = require('../utils/asyncHandler');
const { success } = require('../utils/apiResponse');
const container = require('../helpers/container');

const getPlacesService = () => container.get('placesService');

const autocomplete = asyncHandler(async (req, res) => {
  const data = await getPlacesService().autocomplete(req.query);
  return success(res, data, 'OK');
});

const details = asyncHandler(async (req, res) => {
  const data = await getPlacesService().details(req.query);
  return success(res, data, 'OK');
});

module.exports = {
  autocomplete,
  details,
};

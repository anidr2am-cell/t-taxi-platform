const asyncHandler = require('../utils/asyncHandler');
const { success } = require('../utils/apiResponse');
const container = require('../helpers/container');

const getFlightService = () => container.get('flightService');

const searchFlights = asyncHandler(async (req, res) => {
  const data = await getFlightService().search(req.query);
  return success(res, data, 'OK');
});

module.exports = {
  searchFlights,
};

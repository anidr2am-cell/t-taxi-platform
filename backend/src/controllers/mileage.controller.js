const asyncHandler = require('../utils/asyncHandler');
const { success } = require('../utils/apiResponse');
const container = require('../helpers/container');

const getMileageService = () => container.get('mileageService');

const getBalance = asyncHandler(async (req, res) => {
  const balance = await getMileageService().getBalance(req.user.id);
  return success(res, { balance }, 'OK');
});

const getTransactions = asyncHandler(async (req, res) => {
  const data = await getMileageService().getTransactionHistoryForCustomer(
    req.user.id,
    req.query,
  );
  return success(res, data, 'OK');
});

module.exports = {
  getBalance,
  getTransactions,
};

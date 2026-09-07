const asyncHandler = require('../utils/asyncHandler');
const { success } = require('../utils/apiResponse');
const container = require('../helpers/container');

const getCustomerProfileService = () => container.get('customerProfileService');

const updateProfile = asyncHandler(async (req, res) => {
  const data = await getCustomerProfileService().updateProfile(req.user.id, req.body);
  return success(res, data, 'Profile updated');
});

module.exports = {
  updateProfile,
};

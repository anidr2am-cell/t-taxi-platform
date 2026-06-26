const asyncHandler = require('../utils/asyncHandler');
const { success } = require('../utils/apiResponse');
const HTTP_STATUS = require('../constants/httpStatus');
const container = require('../helpers/container');

const getAuthService = () => container.get('authService');

const register = asyncHandler(async (req, res) => {
  const data = await getAuthService().register(req.body);
  return success(res, data, 'Registered', HTTP_STATUS.CREATED);
});

const login = asyncHandler(async (req, res) => {
  const data = await getAuthService().login(req.body);
  return success(res, data, 'Login successful');
});

const refresh = asyncHandler(async (req, res) => {
  const data = await getAuthService().refresh(req.body.refreshToken);
  return success(res, data, 'Token refreshed');
});

const logout = asyncHandler(async (req, res) => {
  await getAuthService().logout(req.body?.refreshToken);
  return success(res, null, 'Logged out');
});

const me = asyncHandler(async (req, res) => {
  const data = await getAuthService().getMe(req.user.id);
  return success(res, data, 'OK');
});

module.exports = {
  register,
  login,
  refresh,
  logout,
  me,
};

const asyncHandler = require('../utils/asyncHandler');
const { success } = require('../utils/apiResponse');
const container = require('../helpers/container');

const service = () => container.get('platformSettingsService');

const getPublic = asyncHandler(async (_req, res) => success(res, await service().getPublic()));
const getAdmin = asyncHandler(async (_req, res) => success(res, await service().getAdmin()));
const updateAdmin = asyncHandler(async (req, res) => success(
  res, await service().update(req.body, req.user.id), 'Settings updated',
));
const uploadImage = asyncHandler(async (req, res) => success(
  res, await service().saveImage(req.params.kind, req.file, req.user.id), 'Image updated',
));
const getAsset = asyncHandler(async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  return res.sendFile(await service().getImage(req.params.kind));
});

module.exports = { getPublic, getAdmin, updateAdmin, uploadImage, getAsset };

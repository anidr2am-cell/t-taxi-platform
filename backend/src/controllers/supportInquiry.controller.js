const { success, paginate } = require('../utils/apiResponse');
const asyncHandler = require('../utils/asyncHandler');
const path = require('path');
const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const container = require('../helpers/container');

const getService = () => container.get('supportInquiryService');

const handleUploadError = (err, req, res, next) => {
  if (err?.code === 'LIMIT_FILE_SIZE') {
    return next(new AppError('File too large', {
      statusCode: HTTP_STATUS.BAD_REQUEST,
      errorCode: ERROR_CODES.FILE_TOO_LARGE,
    }));
  }
  if (err?.message === 'INVALID_FILE_TYPE') {
    return next(new AppError('Invalid file type', {
      statusCode: HTTP_STATUS.BAD_REQUEST,
      errorCode: ERROR_CODES.INVALID_FILE_TYPE,
      errors: [{
        field: err.fieldName || 'attachments',
        fileName: err.fileName || undefined,
        mimeType: err.mimeType || undefined,
        message: err.reason || 'invalid_file_type',
      }],
    }));
  }
  return next(err);
};

const normalizeMultipartBody = (req, res, next) => {
  if (!req.is('multipart/form-data')) return next();
  req.body = { ...req.body };
  return next();
};

const create = asyncHandler(async (req, res) => {
  const files = Array.isArray(req.files) ? req.files : [];
  const data = await getService().create(req.body, { files });
  return success(res, data, 'Support inquiry received', HTTP_STATUS.CREATED);
});

const getPublicDetail = asyncHandler(async (req, res) => {
  const token = req.get('X-Support-Lookup-Token') || req.query.token;
  const data = await getService().getPublicDetail(req.params.publicId, token);
  return success(res, data, 'OK');
});

const listAdmin = asyncHandler(async (req, res) => {
  const data = await getService().listAdmin(req.query);
  return paginate(res, {
    page: data.page,
    pageSize: data.pageSize,
    total: data.total,
    items: data.items,
  });
});

const getAdminDetail = asyncHandler(async (req, res) => {
  const data = await getService().getAdminDetail(Number(req.params.id));
  return success(res, data, 'OK');
});

const updateAdminStatus = asyncHandler(async (req, res) => {
  const data = await getService().updateStatus(Number(req.params.id), req.body.status);
  return success(res, data, 'Support inquiry status updated');
});

const addAdminMessage = asyncHandler(async (req, res) => {
  const data = await getService().addAdminMessage(Number(req.params.id), req.body, req.user);
  return success(res, data, 'Support inquiry reply sent', HTTP_STATUS.CREATED);
});

const sanitizeHeaderFilename = (name) => path.basename(String(name || 'attachment'))
  .replace(/[\r\n"]/g, '_');

const getAdminAttachment = asyncHandler(async (req, res) => {
  const file = await getService().getAdminAttachmentFile(
    Number(req.params.id),
    Number(req.params.attachmentId),
  );
  const disposition = req.query.download === '1' || req.query.download === 'true'
    ? 'attachment'
    : 'inline';
  res.setHeader('Content-Type', file.mimeType);
  res.setHeader(
    'Content-Disposition',
    `${disposition}; filename="${sanitizeHeaderFilename(file.fileName)}"`,
  );
  return res.sendFile(file.absolutePath);
});

module.exports = {
  handleUploadError,
  normalizeMultipartBody,
  create,
  getPublicDetail,
  listAdmin,
  getAdminDetail,
  updateAdminStatus,
  addAdminMessage,
  getAdminAttachment,
};

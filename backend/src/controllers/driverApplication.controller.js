const asyncHandler = require('../utils/asyncHandler');
const path = require('path');
const { success, paginate } = require('../utils/apiResponse');
const HTTP_STATUS = require('../constants/httpStatus');
const container = require('../helpers/container');
const { uploadDir } = require('../config/multer');

const getService = () => container.get('driverApplicationService');

const normalizeMultipartBody = (req, res, next) => {
  if (!req.is('multipart/form-data')) return next();
  const body = { ...req.body };
  if (body.passwordConfirmation && !body.passwordConfirm) {
    body.passwordConfirm = body.passwordConfirmation;
  }
  if (body.applicantName && !body.fullName) body.fullName = body.applicantName;
  if (!body.email && body.phone) body.email = `${String(body.phone).replace(/\D/g, '')}@driver.local`;
  if (body.licenseNumber && !body.drivingLicenseNumber) {
    body.drivingLicenseNumber = body.licenseNumber;
  }
  if (body.licenseExpiryDate && !body.drivingLicenseExpiryDate) {
    body.drivingLicenseExpiryDate = body.licenseExpiryDate;
  }
  if (!body.vehicleTypeCode && body.vehicleTypeId) {
    body.vehicleTypeCode = `#${body.vehicleTypeId}`;
  }
  if (body.primaryServiceArea && !body.serviceAreas) {
    body.serviceAreas = [body.primaryServiceArea];
  }
  if (typeof body.serviceAreas === 'string') {
    body.serviceAreas = body.serviceAreas.split(',').map((item) => item.trim()).filter(Boolean);
  }
  if (typeof body.languages === 'string') {
    body.languages = body.languages.split(',').map((item) => item.trim()).filter(Boolean);
  }
  body.vehicleOwnershipType = body.vehicleOwnershipType || 'OWNED';
  body.drivingLicenseCountry = body.drivingLicenseCountry || body.countryCode || 'TH';
  body.yearsOfDrivingExperience = body.yearsOfDrivingExperience || 0;
  body.personalDataConsent = body.personalDataConsent ?? true;
  body.driverTermsConsent = body.driverTermsConsent ?? true;
  body.locale = body.locale || 'ko';
  body.countryCode = body.countryCode || 'TH';
  req.body = body;
  return next();
};

const submit = asyncHandler(async (req, res) => {
  const data = await getService().submit(req.body, { files: req.files });
  return success(res, data, 'Driver application submitted', HTTP_STATUS.CREATED);
});

const status = asyncHandler(async (req, res) => {
  const data = await getService().status(req.query);
  return success(res, data, 'OK');
});

const resubmit = asyncHandler(async (req, res) => {
  const data = await getService().resubmit(
    req.params.applicationNumber,
    req.body.token,
    req.body,
    { files: req.files },
  );
  return success(res, data, 'Driver application resubmitted', HTTP_STATUS.CREATED);
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

const getAdminFile = asyncHandler(async (req, res) => {
  const file = await getService().getAdminFile(Number(req.params.id), Number(req.params.fileId));
  const absolute = path.join(uploadDir, file.filePath);
  return res.sendFile(absolute, {
    headers: {
      'Content-Type': file.mimeType || 'application/octet-stream',
      'Content-Disposition': `inline; filename="${file.originalFilename || 'document'}"`,
    },
  });
});

const approve = asyncHandler(async (req, res) => {
  const data = await getService().approve(Number(req.params.id), req.body, req.user, {
    ipAddress: req.ip,
  });
  return success(res, data, 'Driver application approved');
});

const reject = asyncHandler(async (req, res) => {
  const data = await getService().reject(Number(req.params.id), req.body, req.user, {
    ipAddress: req.ip,
  });
  return success(res, data, 'Driver application rejected');
});

module.exports = {
  normalizeMultipartBody,
  submit,
  status,
  resubmit,
  listAdmin,
  getAdminDetail,
  getAdminFile,
  approve,
  reject,
};

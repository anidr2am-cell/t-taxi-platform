const asyncHandler = require('../utils/asyncHandler');
const path = require('path');
const { success, paginate } = require('../utils/apiResponse');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const container = require('../helpers/container');
const { uploadDir } = require('../config/multer');
const AppError = require('../utils/AppError');

const getService = () => container.get('driverApplicationService');

const emptyToNull = (value) => {
  if (value === undefined || value === null) return null;
  if (typeof value === 'string' && value.trim() === '') return null;
  return value;
};

const parseOptionalNumber = (value) => {
  const normalized = emptyToNull(value);
  if (normalized === null) return null;
  const parsed = Number(normalized);
  return Number.isFinite(parsed) ? parsed : normalized;
};

const parseBoolean = (value) => {
  if (value === true || value === 'true' || value === '1' || value === 1) return true;
  if (value === false || value === 'false' || value === '0' || value === 0) return false;
  return value;
};

const parseListField = (value) => {
  const normalized = emptyToNull(value);
  if (normalized === null) return [];
  if (Array.isArray(normalized)) {
    return normalized.map((item) => String(item).trim()).filter(Boolean);
  }
  if (typeof normalized !== 'string') return normalized;
  const trimmed = normalized.trim();
  if (!trimmed) return [];
  if (trimmed.startsWith('[')) {
    try {
      const parsed = JSON.parse(trimmed);
      if (Array.isArray(parsed)) {
        return parsed.map((item) => String(item).trim()).filter(Boolean);
      }
    } catch {
      // Fall back to CSV parsing so validation can report the real field.
    }
  }
  return trimmed.split(',').map((item) => item.trim()).filter(Boolean);
};

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
        field: err.fieldName || 'file',
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
  const body = { ...req.body };
  if (body.passwordConfirmation && !body.passwordConfirm) {
    body.passwordConfirm = body.passwordConfirmation;
  }
  if (body.applicantName && !body.fullName) body.fullName = body.applicantName;
  if (body.licenseNumber && !body.drivingLicenseNumber) {
    body.drivingLicenseNumber = body.licenseNumber;
  }
  if (body.licenseExpiryDate && !body.drivingLicenseExpiryDate) {
    body.drivingLicenseExpiryDate = body.licenseExpiryDate;
  }
  if (!body.vehicleTypeCode && body.vehicleTypeId) {
    body.vehicleTypeCode = `#${body.vehicleTypeId}`;
  }

  for (const field of [
    'vehicleYear',
    'drivingLicenseExpiryDate',
    'email',
    'phoneCountryCode',
    'vehicleMake',
    'vehicleModel',
    'vehicleColor',
    'notes',
    'bankName',
    'bankAccountNumber',
    'bankAccountHolder',
    'lineId',
    'primaryServiceArea',
  ]) {
    body[field] = emptyToNull(body[field]);
  }

  body.vehicleYear = parseOptionalNumber(body.vehicleYear);
  if (body.yearsOfDrivingExperience !== undefined) {
    body.yearsOfDrivingExperience = parseOptionalNumber(body.yearsOfDrivingExperience);
  }

  body.serviceAreas = parseListField(body.serviceAreas);
  body.languages = parseListField(body.languages);
  if (body.primaryServiceArea && body.serviceAreas.length === 0) {
    body.serviceAreas = [body.primaryServiceArea];
  }

  body.personalDataConsent = parseBoolean(body.personalDataConsent);
  body.driverTermsConsent = parseBoolean(body.driverTermsConsent);

  body.vehicleOwnershipType = body.vehicleOwnershipType || 'OWNED';
  body.drivingLicenseCountry = body.drivingLicenseCountry || body.countryCode || 'TH';
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
  handleUploadError,
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

const AppError = require("../utils/AppError");
const HTTP_STATUS = require("../constants/httpStatus");
const ERROR_CODES = require("../constants/errorCodes");

function assertDriverOperational(driver) {
  if (driver?.status !== "SUSPENDED") return driver;
  throw new AppError("Driver account is suspended", {
    statusCode: HTTP_STATUS.FORBIDDEN,
    errorCode: ERROR_CODES.DRIVER_SUSPENDED,
  });
}

module.exports = { assertDriverOperational };

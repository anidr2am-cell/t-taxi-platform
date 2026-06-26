/**
 * utils/apiResponse.js — Standard API envelope (OpenAPI contract)
 *
 * Controller는 res.json() 직접 호출 대신 success()/paginate() 사용 권장
 */
const HTTP_STATUS = require('../constants/httpStatus');

function success(res, data = null, message = 'OK', statusCode = HTTP_STATUS.OK) {
  return res.status(statusCode).json({
    success: true,
    message,
    data,
  });
}

function paginate(res, { page, pageSize, total, items }, message = 'OK') {
  return res.status(HTTP_STATUS.OK).json({
    success: true,
    message,
    data: {
      page,
      page_size: pageSize,
      total,
      items,
    },
  });
}

module.exports = {
  success,
  paginate,
};

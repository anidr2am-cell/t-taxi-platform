/**
 * middlewares/validate.middleware.js — Joi schema validation
 *
 * 사용:
 * validate({ body: loginSchema })
 */
const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');

function validate(schemas = {}) {
  return (req, res, next) => {
    const errors = [];

    for (const [source, schema] of Object.entries(schemas)) {
      if (!schema) continue;
      const { error, value } = schema.validate(req[source], {
        abortEarly: false,
        stripUnknown: true,
      });

      if (error) {
        errors.push(
          ...error.details.map((d) => ({
            field: d.path.join('.'),
            message: d.message,
            type: d.type,
            source,
          })),
        );
      } else {
        req[source] = value;
      }
    }

    if (errors.length > 0) {
      return next(
        new AppError('Validation failed', {
          statusCode: HTTP_STATUS.BAD_REQUEST,
          errorCode: ERROR_CODES.VALIDATION_ERROR,
          errors,
        }),
      );
    }

    next();
  };
}

module.exports = validate;

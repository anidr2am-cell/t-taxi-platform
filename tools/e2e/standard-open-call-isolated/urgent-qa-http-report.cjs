'use strict';

/** Safe subset of booking API error responses (no tokens, passwords, or request echo). */
function bookingHttpErrorReport(httpStatus, json) {
  const body = json && typeof json === 'object' ? json : {};
  const errors = Array.isArray(body.errors) ? body.errors : [];
  return {
    httpStatus,
    errorCode: body.error_code ?? body.code ?? body.errorCode ?? null,
    validation: errors.map((item) => ({
      field: item.field ?? null,
      type: item.type ?? null,
      source: item.source ?? null,
    })),
  };
}

function formatBookingCreateFailure(httpStatus, json) {
  return `create_urgent_${httpStatus}:${JSON.stringify(bookingHttpErrorReport(httpStatus, json))}`;
}

module.exports = {
  bookingHttpErrorReport,
  formatBookingCreateFailure,
};

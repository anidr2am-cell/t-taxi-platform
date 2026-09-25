#!/usr/bin/env node
'use strict';

const path = require('node:path');
const { buildUrgentBookingBody } = require('./urgent-booking-body.cjs');

const BACKEND_ROOT = process.env.BACKEND_ROOT || path.join(__dirname, '..', '..', '..', 'backend');
const { createBookingSchema } = require(path.join(BACKEND_ROOT, 'src', 'validators', 'booking.validator.js'));

const minutes = [50, 55, 70, 80];
const report = {
  backendRoot: BACKEND_ROOT,
  samples: [],
  allPass: true,
};

for (const m of minutes) {
  const body = buildUrgentBookingBody(m, `verify-${m}`);
  const result = createBookingSchema.validate(body, { abortEarly: false, stripUnknown: true });
  const entry = {
    minutesFromNow: m,
    pass: !result.error,
    fields: result.error
      ? result.error.details.map((d) => ({
        field: d.path.join('.') || null,
        type: d.type,
      }))
      : [],
  };
  if (result.error) report.allPass = false;
  report.samples.push(entry);
}

console.log(JSON.stringify(report, null, 2));
process.exit(report.allPass ? 0 : 1);

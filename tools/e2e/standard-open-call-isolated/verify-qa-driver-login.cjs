#!/usr/bin/env node
'use strict';

// PC: QA_API_BASE=http://127.0.0.1:13001/api/v1 node verify-qa-driver-login.cjs [phone]
// Server (in API container): default http://127.0.0.1:3000/api/v1

const { loginDriverApi } = require('./qa-ui-driver-auth.cjs');

const QA_API = (process.env.QA_API_BASE || 'http://127.0.0.1:13001/api/v1').replace(/\/$/, '');
const phone = process.argv[2] || '1111111';

(async () => {
  const r = await loginDriverApi(QA_API, phone);
  const report = {
    executedAt: new Date().toISOString(),
    apiBase: QA_API,
    phone,
    httpStatus: r.httpStatus,
    errorCode: r.errorCode,
    role: r.role,
    loginPass: r.loginOk,
  };
  console.log(JSON.stringify(report, null, 2));
  process.exitCode = r.loginOk ? 0 : 1;
})().catch((err) => {
  console.error('VERIFY_QA_DRIVER_LOGIN_FAIL', err.message);
  process.exitCode = 1;
});

'use strict';

const { resolveQaDriverPassword } = require('./qa-driver-password.cjs');

const UI_DRIVER_ROWS = [
  { id: 10, email: 'qa-oc-driver-clean@example.invalid', phone: '1111111' },
  { id: 11, email: 'qa-oc-driver-busy@example.invalid', phone: '1111111002' },
];

/**
 * POST /auth/login with phone. Returns status/errorCode only (no token in return value for logging).
 */
async function loginDriverApi(apiBase, phone, password) {
  const pw = password ?? resolveQaDriverPassword();
  const base = String(apiBase || '').replace(/\/$/, '');
  const res = await fetch(`${base}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ phone: String(phone).trim(), password: pw }),
  });
  let json = {};
  try {
    json = await res.json();
  } catch {
    json = {};
  }
  const data = json.data ?? json;
  const errorCode = json.errorCode ?? data?.errorCode ?? null;
  const accessToken = data?.accessToken ?? null;
  const role = data?.user?.role ?? null;
  return {
    httpStatus: res.status,
    errorCode,
    accessToken,
    role,
    loginOk: res.status === 200 && role === 'DRIVER' && Boolean(accessToken),
  };
}

module.exports = {
  UI_DRIVER_ROWS,
  loginDriverApi,
  resolveQaDriverPassword,
};

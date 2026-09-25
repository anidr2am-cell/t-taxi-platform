// Mint QA JWTs inside API container — write to file only (never stdout).
const { createRequire } = require('node:module');
const fs = require('node:fs');
const requireBackend = createRequire(`${process.cwd()}/package.json`);
const jwt = requireBackend('jsonwebtoken');

const out = process.env.QA_TOKEN_FILE || '/srv/tride/backend/.qa-tokens.json';
const driverUserId = Number(process.env.QA_DRIVER_USER_ID || 11);
const customerUserId = Number(process.env.QA_CUSTOMER_USER_ID || 2);
const payload = {
  admin: jwt.sign(
    { sub: 1, role: 'ADMIN', email: 'qa-oc-admin@example.invalid', type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '30m' },
  ),
  customer: jwt.sign(
    { sub: customerUserId, role: 'CUSTOMER', email: 'qa-oc-customer@example.invalid', type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '30m' },
  ),
  driver: jwt.sign(
    { sub: driverUserId, role: 'DRIVER', email: `qa-oc-driver-${driverUserId}@example.invalid`, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '30m' },
  ),
};
fs.writeFileSync(out, JSON.stringify(payload), { mode: 0o600 });
console.log(JSON.stringify({ written: out, driverUserId, roles: ['admin', 'customer', 'driver'] }));

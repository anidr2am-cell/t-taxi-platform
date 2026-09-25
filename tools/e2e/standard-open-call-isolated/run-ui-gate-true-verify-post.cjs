// Admin verify pending customer booking for gate=true UI manifest (no secrets logged).
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { createRequire } = require('node:module');

const manifestPath = process.env.UI_MANIFEST || '/srv/tride/backend/ui-manifest.json';
const QA_API = (process.env.QA_API_BASE || 'http://127.0.0.1:3000/api/v1').replace(/\/$/, '');

const requireBackend = createRequire(`${process.cwd()}/package.json`);
const jwt = requireBackend('jsonwebtoken');

const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const bn = manifest.bookings?.gateTrueCustomerPending;
assert.ok(bn, 'gateTrueCustomerPending missing from manifest');

const adminToken = jwt.sign(
  { sub: 1, role: 'ADMIN', email: 'qa-oc-admin@example.invalid', type: 'access' },
  process.env.JWT_ACCESS_SECRET,
  { expiresIn: '30m' },
);

(async () => {
  const res = await fetch(`${QA_API}/admin/bookings/${bn}/contact/verify`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${adminToken}` },
  });
  const json = await res.json();
  assert.equal(res.status, 200, JSON.stringify(json));
  manifest.bookings.gateTrueCustomerVerified = bn;
  manifest.contactVerifiedAt = new Date().toISOString();
  fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2));
  console.log(JSON.stringify({ ok: true, bookingNumber: bn, httpStatus: res.status }));
})().catch((e) => {
  console.error('UI_GATE_TRUE_VERIFY_POST_FAIL', e.message);
  process.exitCode = 1;
});

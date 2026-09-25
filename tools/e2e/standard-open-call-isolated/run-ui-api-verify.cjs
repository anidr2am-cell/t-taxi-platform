// API-level checks for driver open list vs UI manifest (Flutter UI checked separately).
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { loginDriverApi } = require('./qa-ui-driver-auth.cjs');

const manifestPath = process.env.UI_MANIFEST || '/srv/tride/backend/ui-manifest.json';
const QA_API = (process.env.QA_API_BASE || 'http://127.0.0.1:3000/api/v1').replace(/\/$/, '');
const PHASE = (process.env.UI_VERIFY_PHASE || 'full').toLowerCase();

const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const driverPhone = manifest.driverLoginPhone || '1111111';

async function openCalls(token) {
  const res = await fetch(`${QA_API}/driver/calls/open`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  const json = await res.json();
  assert.equal(res.status, 200, JSON.stringify(json));
  const data = json.data ?? json;
  const items = data.items ?? data.calls ?? data;
  return Array.isArray(items) ? items : [];
}

function numbers(calls) {
  return new Set(calls.map((c) => c.bookingNumber ?? c.booking_number));
}

(async () => {
  const login = await loginDriverApi(QA_API, driverPhone);
  const checks = [
    {
      id: 'UI-LOGIN',
      pass: login.loginOk,
      httpStatus: login.httpStatus,
      errorCode: login.errorCode,
      note: 'driver phone login via POST /auth/login (matches Flutter /driver/login)',
    },
  ];

  if (!login.loginOk || !login.accessToken) {
    const report = {
      executedAt: new Date().toISOString(),
      phase: PHASE,
      gate: manifest.gate,
      checks,
      allPass: false,
      note: 'Login failed — open-list checks skipped',
    };
    console.log(JSON.stringify(report, null, 2));
    process.exitCode = 1;
    return;
  }

  const calls = await openCalls(login.accessToken);
  const visible = numbers(calls);
  const b = manifest.bookings;

  if (!manifest.gate) {
    checks.push({
      id: 'UI-A',
      pass: visible.has(b.gateFalseCustomer),
      expectedVisible: b.gateFalseCustomer,
      note: 'gate=false customer STANDARD in open list',
    });
    checks.push({
      id: 'UI-B',
      pass: visible.has(b.gateFalseBusyPlus61),
      expectedVisible: b.gateFalseBusyPlus61,
      note: 'busy anchor +61m visible',
    });
    checks.push({
      id: 'UI-C',
      pass: !visible.has(b.gateFalseBusyPlus60),
      expectedHidden: b.gateFalseBusyPlus60,
      note: 'busy anchor +60m hidden (boundary)',
    });
    checks.push({
      id: 'UI-E-admin',
      pass: visible.has(b.gateFalseAdminManual),
      expectedVisible: b.gateFalseAdminManual,
      note: 'admin manual visible immediately',
    });
  } else if (PHASE === 'pre') {
    checks.push({
      id: 'UI-D-pre',
      pass: !visible.has(b.gateTrueCustomerPending),
      expectedHidden: b.gateTrueCustomerPending,
      note: 'gate=true customer pending hidden before admin verify',
    });
    checks.push({
      id: 'UI-E-admin-pre',
      pass: visible.has(b.gateTrueAdminManual),
      expectedVisible: b.gateTrueAdminManual,
      note: 'gate=true admin manual visible before customer verify',
    });
  } else if (PHASE === 'post') {
    const verifiedBn = b.gateTrueCustomerVerified || b.gateTrueCustomerPending;
    checks.push({
      id: 'UI-D-post',
      pass: visible.has(verifiedBn),
      expectedVisible: verifiedBn,
      note: 'gate=true customer visible after admin verify',
    });
    checks.push({
      id: 'UI-E-admin-post',
      pass: visible.has(b.gateTrueAdminManual),
      expectedVisible: b.gateTrueAdminManual,
      note: 'gate=true admin manual still visible',
    });
  }

  const report = {
    executedAt: new Date().toISOString(),
    phase: PHASE,
    gate: manifest.gate,
    visibleBookingNumbers: [...visible].sort(),
    visibleCount: visible.size,
    checks,
    allPass: checks.every((c) => c.pass),
    note: 'Driver Flutter/web UI must match these booking numbers on cards',
  };
  console.log(JSON.stringify(report, null, 2));
  if (!report.allPass) process.exitCode = 1;
})().catch((e) => {
  console.error('UI_API_VERIFY_FAIL', e.message);
  process.exitCode = 1;
});

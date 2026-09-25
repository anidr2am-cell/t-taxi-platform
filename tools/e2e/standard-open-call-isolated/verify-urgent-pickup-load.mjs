/**
 * Local harness check: same createRequire path as urgent matrix/smoke runners.
 * Does not create bookings or run the full suite.
 */
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const BACKEND_ROOT = (process.env.SOCKET_BACKEND_ROOT || ROOT).replace(/\\/g, '/');
const pkgPath = path.join(BACKEND_ROOT, 'package.json');
const requireBackend = createRequire(pathToFileURL(pkgPath).href);
const pickupMod = requireBackend('./urgent-qa-pickup.cjs');
const urgentPickupIso = pickupMod.urgentPickupIso;

const report = {
  backendRoot: BACKEND_ROOT,
  loadPath: './urgent-qa-pickup.cjs',
  typeofExport: typeof urgentPickupIso,
  ok: false,
};

if (typeof urgentPickupIso !== 'function') {
  console.log(JSON.stringify({ ...report, reason: 'urgentPickupIso_not_function' }, null, 2));
  process.exit(1);
}

const iso = urgentPickupIso(75);
const t = Date.parse(iso);
const now = Date.now();
const max = now + 2 * 60 * 60 * 1000;
report.iso = iso;
report.future = t > now;
report.within2h = t < max;
report.ok = Number.isFinite(t) && report.future && report.within2h;

console.log(JSON.stringify(report, null, 2));
process.exit(report.ok ? 0 : 1);

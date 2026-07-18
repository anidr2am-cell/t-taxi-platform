const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const DEFAULT_ALLOWED_HOSTS = new Set(['localhost', '127.0.0.1', 'trider.taxi']);
const BLOCKED_HOST_PATTERNS = [/88taxi\.net$/i, /ktaxi/i, /production/i, /prod/i];
const SECRET_KEY_PATTERN = /(password|token|secret|authorization|guestAccessToken|accessToken|refreshToken)/i;
const TOKEN_VALUE_PATTERN = /([A-Za-z0-9_-]{18,}\.[A-Za-z0-9._-]{18,}|[A-Za-z0-9_-]{32,})/g;
const TOKEN_QUERY_VALUE_PATTERN = /([A-Za-z0-9_-]{18,}\.[A-Za-z0-9._-]{18,}|[A-Za-z0-9_-]{32,})/;
const E2E_MARKER = 'CUSTOMER_DRIVER_LOCATION_E2E';
const TEST_NAME_PREFIX = '[E2E]';
const TERMINAL_STATUSES = new Set(['SETTLEMENT_PENDING', 'COMPLETED', 'CANCELLED', 'NO_SHOW']);
const ACTIVE_STATUSES = new Set(['ON_ROUTE', 'DRIVER_ARRIVED', 'PICKED_UP']);

function repoRoot() {
  return path.resolve(__dirname, '..', '..', '..');
}

function loadEnvFile(filePath = path.join(repoRoot(), '.env.e2e.local')) {
  if (!fs.existsSync(filePath)) return {};
  const values = {};
  const text = fs.readFileSync(filePath, 'utf8');
  for (const line of text.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const index = trimmed.indexOf('=');
    if (index < 0) continue;
    const key = trimmed.slice(0, index).trim();
    let value = trimmed.slice(index + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    values[key] = value;
  }
  return values;
}

function mergeEnv(fileValues = {}, runtimeEnv = process.env) {
  return { ...fileValues, ...runtimeEnv };
}

function normalizeBaseUrl(value) {
  return String(value ?? '').trim().replace(/\/+$/, '');
}

function allowedHostsFromEnv(value) {
  const hosts = new Set(DEFAULT_ALLOWED_HOSTS);
  for (const host of String(value ?? '').split(',')) {
    const normalized = host.trim().toLowerCase();
    if (normalized) hosts.add(normalized);
  }
  return hosts;
}

function assertUrlAllowed(label, value, env = process.env) {
  const normalized = normalizeBaseUrl(value);
  if (!normalized) {
    throw new Error(`${label} is required`);
  }
  const url = new URL(normalized);
  if (!['http:', 'https:'].includes(url.protocol)) {
    throw new Error(`${label} must be http or https`);
  }
  const host = url.hostname.toLowerCase();
  if (BLOCKED_HOST_PATTERNS.some((pattern) => pattern.test(host))) {
    throw new Error(`${label} points to a blocked host: ${host}`);
  }
  const allowedHosts = allowedHostsFromEnv(env.TRIDE_E2E_ALLOWED_HOSTS);
  if (!allowedHosts.has(host)) {
    throw new Error(`${label} host is not whitelisted for staging E2E: ${host}`);
  }
  return normalized;
}

function buildConfig(env = process.env, { requireSecrets = false } = {}) {
  if (env.TRIDE_E2E_TARGET !== 'staging') {
    throw new Error('TRIDE_E2E_TARGET=staging is required');
  }
  const frontendUrl = assertUrlAllowed(
    'TRIDE_E2E_FRONTEND_URL',
    env.TRIDE_E2E_FRONTEND_URL,
    env,
  );
  const backendUrl = assertUrlAllowed(
    'TRIDE_E2E_BACKEND_URL',
    env.TRIDE_E2E_BACKEND_URL,
    env,
  );

  const requiredForLive = [
    'TRIDE_E2E_ADMIN_EMAIL',
    'TRIDE_E2E_ADMIN_PASSWORD',
    'TRIDE_E2E_DRIVER_EMAIL',
    'TRIDE_E2E_DRIVER_PASSWORD',
    'TRIDE_E2E_DRIVER_ID',
    'TRIDE_E2E_CUSTOMER_PHONE',
  ];
  if (requireSecrets) {
    const missing = requiredForLive.filter((key) => !env[key]);
    if (missing.length) {
      throw new Error(`Missing live E2E variables: ${missing.join(', ')}`);
    }
    const driverId = Number(env.TRIDE_E2E_DRIVER_ID);
    if (!Number.isInteger(driverId) || driverId <= 0) {
      throw new Error('TRIDE_E2E_DRIVER_ID must be a positive integer');
    }
    if (env.TRIDE_E2E_ALLOW_LIVE !== '1') {
      throw new Error('TRIDE_E2E_ALLOW_LIVE=1 is required for live staging E2E');
    }
  }

  return {
    target: env.TRIDE_E2E_TARGET,
    frontendUrl,
    backendUrl,
    adminEmail: env.TRIDE_E2E_ADMIN_EMAIL || '',
    adminPassword: env.TRIDE_E2E_ADMIN_PASSWORD || '',
    driverEmail: env.TRIDE_E2E_DRIVER_EMAIL || '',
    driverPassword: env.TRIDE_E2E_DRIVER_PASSWORD || '',
    driverId: env.TRIDE_E2E_DRIVER_ID ? Number(env.TRIDE_E2E_DRIVER_ID) : null,
    customerPhone: env.TRIDE_E2E_CUSTOMER_PHONE || '+66000000001',
    headed: env.TRIDE_E2E_HEADED === '1',
    keepFixture: env.TRIDE_E2E_KEEP_FIXTURE === '1',
    artifactDir: env.TRIDE_E2E_ARTIFACT_DIR || path.join(repoRoot(), 'e2e-artifacts'),
    pollIntervalMs: Number(env.TRIDE_E2E_EXPECTED_POLL_MS || 15000),
  };
}

function createRunId(now = new Date(), randomBytes = crypto.randomBytes(2)) {
  const stamp = now.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, '');
  return `E2E-${stamp}-${randomBytes.toString('hex')}`;
}

function fixtureCustomer(runId, phone) {
  return {
    name: `${TEST_NAME_PREFIX} Customer ${runId}`,
    email: `customer-${runId.toLowerCase()}@example.com`,
    phone,
    countryCode: 'TH',
  };
}

function futurePickup(now = new Date()) {
  const date = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);
  date.setUTCHours(3, 30, 0, 0);
  return date.toISOString();
}

function buildBookingPayload(runId, phone, now = new Date()) {
  return {
    serviceTypeCode: 'AIRPORT_PICKUP',
    vehicleTypeCode: 'SUV',
    vehicleCount: 1,
    scheduledPickupAt: futurePickup(now),
    origin: {
      name: 'Suvarnabhumi Airport',
      address: 'Suvarnabhumi Airport, Bangkok, Thailand',
      placeId: `e2e-origin-${runId}`,
    },
    destination: {
      name: 'Pattaya',
      address: 'Pattaya, Chon Buri, Thailand',
      placeId: `e2e-destination-${runId}`,
    },
    originAirportIata: 'BKK',
    destinationLocationCode: 'PATTAYA',
    passengers: { adults: 2, children: 0, infants: 0 },
    luggage: { carriers20Inch: 1, carriers24InchPlus: 1, golfBags: 0 },
    options: { nameSign: true },
    transfer: { airportIata: 'BKK', flightNumber: 'TG401' },
    customer: fixtureCustomer(runId, phone),
    additionalRequests: `${E2E_MARKER} ${runId}`,
    specialRequests: `${E2E_MARKER} ${runId}`,
  };
}

function redactString(value) {
  return String(value ?? '')
    .replace(/Bearer\s+[A-Za-z0-9._-]+/gi, 'Bearer [REDACTED]')
    .replace(TOKEN_VALUE_PATTERN, (match) => (match.length >= 32 ? '[REDACTED]' : match));
}

function redact(value) {
  if (Array.isArray(value)) return value.map((item) => redact(item));
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([key, item]) => [
        key,
        SECRET_KEY_PATTERN.test(key) ? '[REDACTED]' : redact(item),
      ]),
    );
  }
  if (typeof value === 'string') return redactString(value);
  return value;
}

function sanitizeUrl(value) {
  const url = new URL(value);
  url.search = '';
  url.hash = '';
  return url.toString();
}

function classifyNetworkUrl(value) {
  const url = new URL(value);
  const pathName = url.pathname;
  if (pathName === '/api/v1/public/bookings/lookup') return 'guestLookup';
  if (/\/api\/v1\/public\/bookings\/\d+\/driver-location$/.test(pathName)) {
    return 'guestLocation';
  }
  if (pathName.startsWith('/socket.io')) return 'socket';
  if (pathName.includes('driver-location')) return 'driverLocationOther';
  return 'other';
}

function assertNoTokenInUrl(value) {
  const url = new URL(value);
  for (const [key, val] of url.searchParams.entries()) {
    if (SECRET_KEY_PATTERN.test(key) || TOKEN_QUERY_VALUE_PATTERN.test(val)) {
      throw new Error(`Secret-like query parameter is not allowed in E2E URL: ${key}`);
    }
  }
}

class NetworkAudit {
  constructor() {
    this.events = [];
  }

  recordRequest(url, method = 'GET') {
    assertNoTokenInUrl(url);
    this.events.push({
      type: 'request',
      category: classifyNetworkUrl(url),
      method,
      url: sanitizeUrl(url),
      at: Date.now(),
    });
  }

  counts() {
    return this.events.reduce((acc, event) => {
      acc[event.category] = (acc[event.category] || 0) + 1;
      return acc;
    }, {});
  }

  assertNoRepeatedGuestLookup(maxAllowed = 1) {
    const count = this.counts().guestLookup || 0;
    if (count > maxAllowed) {
      throw new Error(`Guest lookup endpoint was called ${count} times`);
    }
  }

  assertSocketSubscribeLimit(maxAllowed = 1) {
    const count = this.events.filter((event) => event.category === 'socket').length;
    if (count > maxAllowed) {
      throw new Error(`Socket connection/subscription repeated ${count} times`);
    }
  }

  assertLocationPollingObserved() {
    const count = this.counts().guestLocation || 0;
    if (count < 1) {
      throw new Error('Guest driver location polling was not observed');
    }
  }
}

function assertCleanupCandidate(record) {
  if (!record || typeof record !== 'object') throw new Error('Cleanup record is required');
  if (!String(record.runId || '').startsWith('E2E-')) {
    throw new Error('Cleanup refused a record without an E2E run ID');
  }
  if (!String(record.customerName || '').startsWith(TEST_NAME_PREFIX)) {
    throw new Error('Cleanup refused a non-E2E customer name');
  }
  if (!String(record.marker || '').includes(E2E_MARKER)) {
    throw new Error('Cleanup refused a record without the E2E marker');
  }
  return true;
}

module.exports = {
  ACTIVE_STATUSES,
  DEFAULT_ALLOWED_HOSTS,
  E2E_MARKER,
  NetworkAudit,
  TERMINAL_STATUSES,
  TEST_NAME_PREFIX,
  assertCleanupCandidate,
  assertNoTokenInUrl,
  assertUrlAllowed,
  buildBookingPayload,
  buildConfig,
  classifyNetworkUrl,
  createRunId,
  fixtureCustomer,
  loadEnvFile,
  mergeEnv,
  normalizeBaseUrl,
  redact,
  redactString,
  repoRoot,
  sanitizeUrl,
};

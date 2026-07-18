const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const HARD_ALLOWED_HOSTS = new Set(['localhost', '127.0.0.1', 'trider.taxi']);
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

function assertUrlAllowed(label, value) {
  const normalized = normalizeBaseUrl(value);
  if (!normalized) {
    throw new Error(`${label} is required`);
  }
  const url = new URL(normalized);
  if (!['http:', 'https:'].includes(url.protocol)) {
    throw new Error(`${label} must be http or https`);
  }
  if (url.username || url.password) {
    throw new Error(`${label} must not contain credentials`);
  }
  const host = url.hostname.toLowerCase();
  if (BLOCKED_HOST_PATTERNS.some((pattern) => pattern.test(host))) {
    throw new Error(`${label} points to a blocked host: ${host}`);
  }
  if (!HARD_ALLOWED_HOSTS.has(host)) {
    throw new Error(`${label} host is not hard-allowed for staging E2E: ${host}`);
  }
  if (host !== 'localhost' && host !== '127.0.0.1' && url.protocol !== 'https:') {
    throw new Error(`${label} must use HTTPS for staging hosts`);
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
  );
  const backendUrl = assertUrlAllowed(
    'TRIDE_E2E_BACKEND_URL',
    env.TRIDE_E2E_BACKEND_URL,
  );

  const frontendHost = new URL(frontendUrl).hostname.toLowerCase();
  const backendHost = new URL(backendUrl).hostname.toLowerCase();
  if (frontendHost !== backendHost && env.TRIDE_E2E_ALLOW_SPLIT_HOSTS !== '1') {
    throw new Error('Frontend and backend hosts must match unless TRIDE_E2E_ALLOW_SPLIT_HOSTS=1');
  }

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
    frontendHost,
    backendHost,
    allowedHosts: [...HARD_ALLOWED_HOSTS].sort(),
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

function createViewportRunId(baseRunId, viewport) {
  return `${baseRunId}-${viewport.width}`;
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

function tokenFingerprint(value) {
  if (!value) return null;
  return crypto.createHash('sha256').update(String(value)).digest('hex').slice(0, 8);
}

function redactString(value) {
  return String(value ?? '')
    .replace(/Bearer\s+[A-Za-z0-9._-]+/gi, 'Bearer [REDACTED]')
    .replace(TOKEN_VALUE_PATTERN, (match) => (match.length >= 32 ? '[REDACTED]' : match));
}

function redact(value) {
  if (value instanceof Error) return serializeSafeError(value);
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

function serializeSafeError(error, { includeStack = false } = {}) {
  const safe = {
    name: error?.name || 'Error',
    message: redactString(error?.message || String(error)),
  };
  if (includeStack && error?.stack) safe.stack = redactString(error.stack);
  return safe;
}

function sanitizeUrl(value) {
  const url = new URL(value);
  url.search = '';
  url.hash = '';
  url.username = '';
  url['password'] = '';
  return url.toString();
}

function classifyNetworkUrl(value) {
  const url = new URL(value);
  const pathName = url.pathname;
  if (pathName === '/api/v1/public/bookings/lookup') return 'guestLookup';
  if (/\/api\/v1\/public\/bookings\/\d+\/driver-location$/.test(pathName)) {
    return 'guestLocation';
  }
  if (pathName.startsWith('/socket.io')) return 'socketTransport';
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
    this.webSockets = [];
  }

  recordRequest(url, method = 'GET', headers = {}) {
    assertNoTokenInUrl(url);
    const guestToken = headers['x-guest-access-token'] || headers['X-Guest-Access-Token'];
    this.events.push({
      type: 'request',
      category: classifyNetworkUrl(url),
      method,
      url: sanitizeUrl(url),
      guestTokenFingerprint: guestToken ? tokenFingerprint(guestToken) : null,
      at: Date.now(),
    });
  }

  recordWebSocket(url) {
    assertNoTokenInUrl(url);
    this.webSockets.push({
      type: 'websocket',
      url: sanitizeUrl(url),
      at: Date.now(),
      closedAt: null,
    });
  }

  recordWebSocketClosed(url) {
    const safeUrl = sanitizeUrl(url);
    const open = [...this.webSockets].reverse().find(
      (socket) => socket.url === safeUrl && socket.closedAt == null,
    );
    if (open) open.closedAt = Date.now();
  }

  counts() {
    return this.events.reduce((acc, event) => {
      acc[event.category] = (acc[event.category] || 0) + 1;
      return acc;
    }, {});
  }

  eventsFor(category) {
    return this.events.filter((event) => event.category === category);
  }

  assertNoRepeatedGuestLookup(maxAllowed = 1) {
    const count = this.counts().guestLookup || 0;
    if (count > maxAllowed) {
      throw new Error(`Guest lookup endpoint was called ${count} times`);
    }
  }

  assertLocationPollingObserved(minAllowed = 1) {
    const count = this.counts().guestLocation || 0;
    if (count < minAllowed) {
      throw new Error(`Guest driver location polling observed ${count}, expected at least ${minAllowed}`);
    }
  }

  assertGuestLocationInterval({ expectedMs, toleranceMs = 6000 }) {
    const events = this.eventsFor('guestLocation');
    if (events.length < 2) {
      throw new Error('At least two guest location requests are required to verify polling interval');
    }
    const interval = events[events.length - 1].at - events[events.length - 2].at;
    if (Math.abs(interval - expectedMs) > toleranceMs) {
      throw new Error(`Guest location polling interval ${interval}ms is outside expected ${expectedMs}ms`);
    }
  }

  assertStableGuestTokenFingerprint() {
    const fingerprints = new Set(
      this.eventsFor('guestLocation')
        .map((event) => event.guestTokenFingerprint)
        .filter(Boolean),
    );
    if (fingerprints.size > 1) {
      throw new Error('Guest location requests used multiple guest token fingerprints');
    }
  }

  assertNoGuestLocationAfter(cutoffMs, graceMs = 1000) {
    const late = this.eventsFor('guestLocation').filter((event) => event.at > cutoffMs + graceMs);
    if (late.length) {
      throw new Error(`Guest location polling continued after terminal state (${late.length} late requests)`);
    }
  }

  assertWebSocketConnectionLimit(maxAllowed = 1) {
    if (this.webSockets.length > maxAllowed) {
      throw new Error(`WebSocket connections repeated ${this.webSockets.length} times`);
    }
  }

  assertSocketSubscribeLimit(maxAllowed = 1) {
    this.assertWebSocketConnectionLimit(maxAllowed);
  }

  socketReconnectCount() {
    return Math.max(0, this.webSockets.length - 1);
  }
}

function assertCleanupCandidate(record) {
  if (!record || typeof record !== 'object') throw new Error('Cleanup record is required');
  if (!String(record.runId || '').startsWith('E2E-')) {
    throw new Error('Cleanup refused a record without an E2E run ID');
  }
  if (!String(record.bookingNumber || '').startsWith('TX')) {
    throw new Error('Cleanup refused a record without a booking number');
  }
  if (!String(record.customerName || '').startsWith(TEST_NAME_PREFIX)) {
    throw new Error('Cleanup refused a non-E2E customer name');
  }
  if (!String(record.marker || '').includes(E2E_MARKER)) {
    throw new Error('Cleanup refused a record without the E2E marker');
  }
  return true;
}

function assertServerCleanupCandidate(record, serverBooking) {
  assertCleanupCandidate(record);
  if (!serverBooking || typeof serverBooking !== 'object') {
    throw new Error('Cleanup refused because server booking detail is missing');
  }
  const serverBookingNumber = String(serverBooking.bookingNumber || serverBooking.booking_number || '');
  if (serverBookingNumber !== record.bookingNumber) {
    throw new Error(`Cleanup refused booking number mismatch for ${record.runId}`);
  }
  const serverCustomerName = String(serverBooking.customer?.name || serverBooking.customerName || '');
  if (!serverCustomerName.startsWith(TEST_NAME_PREFIX)) {
    throw new Error(`Cleanup refused customer name mismatch for ${record.runId}`);
  }
  if (!serverCustomerName.includes(record.runId)) {
    throw new Error(`Cleanup refused customer run ID mismatch for ${record.runId}`);
  }
  const marker = [
    serverBooking.specialRequests,
    serverBooking.additionalRequests,
    serverBooking.luggage?.specialItems,
    serverBooking.requestMarker,
  ].filter(Boolean).join(' ');
  if (!marker.includes(E2E_MARKER)) {
    throw new Error(`Cleanup refused server marker mismatch for ${record.runId}`);
  }
  if (!marker.includes(record.runId)) {
    throw new Error(`Cleanup refused server marker run ID mismatch for ${record.runId}`);
  }
  return true;
}

class FixtureRegistry {
  constructor() {
    this.records = [];
  }

  add(record) {
    if (!record?.runId) throw new Error('Fixture registry requires runId');
    const index = this.records.findIndex((item) => item.runId === record.runId);
    const next = { cleanupStatus: 'pending', ...record };
    if (index >= 0) this.records[index] = { ...this.records[index], ...next };
    else this.records.push(next);
    return this.records.find((item) => item.runId === record.runId);
  }

  update(runId, patch) {
    const record = this.records.find((item) => item.runId === runId);
    if (!record) throw new Error(`Fixture registry missing ${runId}`);
    Object.assign(record, patch);
    return record;
  }

  pending() {
    return this.records.filter((record) => record.cleanupStatus !== 'archived');
  }

  manifest() {
    return this.records.map((record) => redact({
      runId: record.runId,
      viewport: record.viewport,
      bookingNumber: record.bookingNumber,
      customerName: record.customerName,
      marker: record.marker,
      cleanupStatus: record.cleanupStatus,
      cleanupError: record.cleanupError,
    }));
  }
}

module.exports = {
  ACTIVE_STATUSES,
  E2E_MARKER,
  FixtureRegistry,
  HARD_ALLOWED_HOSTS,
  NetworkAudit,
  TERMINAL_STATUSES,
  TEST_NAME_PREFIX,
  assertCleanupCandidate,
  assertNoTokenInUrl,
  assertServerCleanupCandidate,
  assertUrlAllowed,
  buildBookingPayload,
  buildConfig,
  classifyNetworkUrl,
  createRunId,
  createViewportRunId,
  fixtureCustomer,
  loadEnvFile,
  mergeEnv,
  normalizeBaseUrl,
  redact,
  redactString,
  repoRoot,
  sanitizeUrl,
  serializeSafeError,
  tokenFingerprint,
};

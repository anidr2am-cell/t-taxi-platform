const baseUrl = process.env.STAGING_BASE_URL;
const frontendUrl = process.env.STAGING_FRONTEND_URL;
const socketUrl = process.env.STAGING_SOCKET_URL || baseUrl;
const timeoutMs = Number(process.env.STAGING_SMOKE_TIMEOUT_MS || 10000);

if (!baseUrl || !frontendUrl) {
  console.error('STAGING_BASE_URL and STAGING_FRONTEND_URL are required.');
  process.exit(1);
}

async function fetchWithTimeout(url, options = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

async function expectStatus(name, url, allowedStatuses) {
  const response = await fetchWithTimeout(url);
  if (!allowedStatuses.includes(response.status)) {
    throw new Error(`${name} returned ${response.status}`);
  }
  console.log(`${name}: ${response.status}`);
  return response;
}

async function checkSocket() {
  const path = process.env.STAGING_SOCKET_PATH || '/socket.io';
  const url = new URL(path, socketUrl);
  url.searchParams.set('EIO', '4');
  url.searchParams.set('transport', 'polling');
  const response = await fetchWithTimeout(url.toString());
  if (response.status !== 200) {
    throw new Error(`Socket.IO handshake returned ${response.status}`);
  }
  console.log('Socket.IO polling handshake: 200');
}

async function main() {
  const apiBase = baseUrl.replace(/\/$/, '');
  const webBase = frontendUrl.replace(/\/$/, '');

  await expectStatus('Frontend root', webBase, [200]);
  await expectStatus('Guest lookup route', `${webBase}/booking/lookup`, [200]);
  await expectStatus('Admin route', `${webBase}/admin`, [200]);
  await expectStatus('Driver route', `${webBase}/driver`, [200]);
  await expectStatus('Health', `${apiBase}/api/v1/health`, [200]);
  await expectStatus('Readiness', `${apiBase}/api/v1/health/readiness`, [200, 503]);
  await expectStatus('Unauthenticated admin boundary', `${apiBase}/api/v1/admin/bookings`, [401, 403]);
  await checkSocket();

  console.log('Staging smoke test completed.');
}

main().catch((error) => {
  console.error(`Staging smoke test failed: ${error.message}`);
  process.exit(1);
});

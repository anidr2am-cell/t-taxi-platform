#!/usr/bin/env node

const baseUrl = String(process.argv[2] || '').replace(/\/$/, '');
const flightNumber = process.argv[3] || 'KE651';
const requestedDate = process.argv[4] || bangkokDatePlusDays(7);

if (!/^https?:\/\//.test(baseUrl)) {
  fail('Usage: node verify-booking-deployment.cjs <base-url> [flight-number] [YYYY-MM-DD]');
}

function bangkokDatePlusDays(days) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Bangkok',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(new Date());
  const values = Object.fromEntries(parts.map(({ type, value }) => [type, value]));
  const bangkokNoonUtc = new Date(`${values.year}-${values.month}-${values.day}T05:00:00Z`);
  bangkokNoonUtc.setUTCDate(bangkokNoonUtc.getUTCDate() + days);
  return bangkokNoonUtc.toISOString().slice(0, 10);
}

function fail(message) {
  console.error(`DEPLOY_VERIFY_FAIL: ${message}`);
  process.exit(1);
}

async function getJson(url) {
  const response = await fetch(url, { redirect: 'follow' });
  const text = await response.text();
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    fail(`${url} returned non-JSON with HTTP ${response.status}`);
  }
  if (response.status !== 200) {
    fail(`${url} returned HTTP ${response.status}`);
  }
  return body;
}

(async () => {
  const pageUrl = `${baseUrl}/booking?service=AIRPORT_PICKUP`;
  const pageResponse = await fetch(pageUrl, { redirect: 'follow' });
  if (pageResponse.status !== 200) {
    fail(`${pageUrl} returned HTTP ${pageResponse.status}`);
  }

  const query = new URLSearchParams({ flightNumber, flightDate: requestedDate });
  const apiUrl = `${baseUrl}/api/v1/public/flights/search?${query}`;
  const body = await getJson(apiUrl);
  const data = body?.data;
  const resultCount = Array.isArray(data?.matches)
    ? data.matches.length
    : data && (data.flightNumber || data.arrival)
      ? 1
      : 0;
  if (body?.success !== true || resultCount < 1) {
    fail(`${apiUrl} did not return success=true with at least one result`);
  }

  console.log(`DEPLOY_VERIFY_PASS page=200 api=200 flight=${flightNumber} date=${requestedDate} results=${resultCount}`);
})().catch((error) => fail(error?.message || String(error)));

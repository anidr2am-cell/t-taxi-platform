const baseUrl = (process.env.STAGING_BASE_URL || 'http://103.60.127.213:3100').replace(/\/$/, '');
const timeoutMs = Number(process.env.STAGING_SMOKE_TIMEOUT_MS || 10000);
const pickupAt = process.env.STAGING_FARE_PICKUP_AT || '2026-07-10T10:00:00+07:00';

const pricedCases = [
  { label: 'BKK → Pattaya SUV', body: { serviceTypeCode: 'AIRPORT_PICKUP', vehicleTypeCode: 'SUV', originAirportIata: 'BKK', destinationLocationCode: 'PATTAYA' }, expected: 1300 },
  { label: 'BKK → Bangkok Sedan', body: { serviceTypeCode: 'AIRPORT_PICKUP', vehicleTypeCode: 'SEDAN', originAirportIata: 'BKK', destinationLocationCode: 'BANGKOK' }, expected: 550 },
  { label: 'BKK → Hua Hin VAN', body: { serviceTypeCode: 'AIRPORT_PICKUP', vehicleTypeCode: 'VAN', originAirportIata: 'BKK', destinationLocationCode: 'HUA_HIN' }, expected: 2700 },
  { label: 'DMK → Pattaya VAN', body: { serviceTypeCode: 'AIRPORT_PICKUP', vehicleTypeCode: 'VAN', originAirportIata: 'DMK', destinationLocationCode: 'PATTAYA' }, expected: 2200 },
  { label: 'Pattaya → DMK VAN', body: { serviceTypeCode: 'AIRPORT_DROPOFF', vehicleTypeCode: 'VAN', originLocationCode: 'PATTAYA', destinationLocationCode: 'DMK' }, expected: 2300 },
  { label: 'Pattaya → Bangkok SUV', body: { serviceTypeCode: 'CITY_TRANSFER', vehicleTypeCode: 'SUV', originLocationCode: 'PATTAYA', destinationLocationCode: 'BANGKOK' }, expected: 1500 },
  { label: 'Bangkok → Pattaya VAN', body: { serviceTypeCode: 'CITY_TRANSFER', vehicleTypeCode: 'VAN', originLocationCode: 'BANGKOK', destinationLocationCode: 'PATTAYA' }, expected: 2000 },
  { label: 'Bangkok → BKK SUV', body: { serviceTypeCode: 'AIRPORT_DROPOFF', vehicleTypeCode: 'SUV', originLocationCode: 'BANGKOK', destinationLocationCode: 'BKK' }, expected: 800 },
];

const inquiryCases = [
  {
    label: 'Bangkok → Hua Hin (outside fare table)',
    body: { serviceTypeCode: 'CITY_TRANSFER', vehicleTypeCode: 'SEDAN', originLocationCode: 'BANGKOK', destinationLocationCode: 'HUA_HIN' },
  },
  {
    label: 'BKK → Pattaya LUXURY (no arbitrary VIP price)',
    body: { serviceTypeCode: 'AIRPORT_PICKUP', vehicleTypeCode: 'LUXURY', originAirportIata: 'BKK', destinationLocationCode: 'PATTAYA' },
  },
];

async function postPricing(body) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(`${baseUrl}/api/v1/bookings/pricing/calculate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...body, scheduledPickupAt: pickupAt, adults: 2 }),
      signal: controller.signal,
    });
    const payload = await response.json().catch(() => ({}));
    return { status: response.status, payload };
  } finally {
    clearTimeout(timer);
  }
}

async function main() {
  for (const fareCase of pricedCases) {
    const { status, payload } = await postPricing(fareCase.body);
    if (status !== 200 || !payload.success) {
      throw new Error(`${fareCase.label}: expected 200 OK but got ${status} ${payload.error_code || ''} ${payload.message || ''}`.trim());
    }
    const total = Number(payload.data?.totalAmount);
    if (total !== fareCase.expected) {
      throw new Error(`${fareCase.label}: expected ${fareCase.expected} THB but got ${total}`);
    }
    console.log(`${fareCase.label}: ${total}`);
  }

  for (const inquiryCase of inquiryCases) {
    const { status, payload } = await postPricing(inquiryCase.body);
    if (status !== 404 || payload.error_code !== 'NOT_FOUND') {
      throw new Error(`${inquiryCase.label}: expected 404 NOT_FOUND but got ${status} ${payload.error_code || ''}`);
    }
    console.log(`${inquiryCase.label}: NOT_FOUND (inquiry path)`);
  }

  console.log('Staging fare table smoke test completed.');
}

main().catch((error) => {
  console.error(`Staging fare table smoke test failed: ${error.message}`);
  process.exit(1);
});

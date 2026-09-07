#!/usr/bin/env node
/**
 * STG coupon smoke test — runs inside tride-backend container.
 * Uses internal JWT minting (no plaintext admin password required).
 */
const crypto = require('node:crypto');
const mysql = require('mysql2/promise');
const jwt = require('jsonwebtoken');

const BASE_URL = process.env.TRIDE_BASE_URL || 'http://127.0.0.1:3000';
const CUSTOMER_EMAIL = process.env.TRIDE_CUSTOMER_EMAIL || 'mileage-deploy-test-20260831@example.com';
const CUSTOMER_PASSWORD = process.env.TRIDE_CUSTOMER_PASSWORD || 'DeployTest123!';

function signAccessToken(user) {
  const secret = process.env.JWT_ACCESS_SECRET;
  if (!secret) throw new Error('JWT_ACCESS_SECRET missing');
  return jwt.sign(
    {
      sub: user.id,
      email: user.email,
      role: user.role,
      type: 'access',
    },
    secret,
    { expiresIn: '1h' },
  );
}

async function fetchJson(path, options = {}) {
  const res = await fetch(`${BASE_URL}${path}`, {
    ...options,
    headers: {
      'content-type': 'application/json',
      ...(options.headers || {}),
    },
  });
  const text = await res.text();
  let body;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    body = { raw: text };
  }
  return { status: res.status, ok: res.ok, body };
}

async function loginCustomer() {
  const { status, body } = await fetchJson('/api/v1/auth/login', {
    method: 'POST',
    body: JSON.stringify({ email: CUSTOMER_EMAIL, password: CUSTOMER_PASSWORD }),
  });
  if (!body?.data?.accessToken) {
    throw new Error(`customer login failed ${status}: ${body?.message || JSON.stringify(body)}`);
  }
  return body.data.accessToken;
}

async function main() {
  const conn = await mysql.createConnection({
    host: process.env.DB_HOST || 'tride-db',
    port: Number(process.env.DB_PORT || 3306),
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
  });

  try {
    const [admins] = await conn.query(
      "SELECT id, email, role FROM users WHERE role IN ('ADMIN','SUPER_ADMIN') AND is_active = 1 AND deleted_at IS NULL ORDER BY id LIMIT 1",
    );
    if (!admins.length) throw new Error('no active admin user');
    const admin = admins[0];
    const adminToken = signAccessToken(admin);

    const [customers] = await conn.query(
      'SELECT id, email FROM users WHERE email = ? AND role = ? AND deleted_at IS NULL LIMIT 1',
      [CUSTOMER_EMAIL, 'CUSTOMER'],
    );
    if (!customers.length) throw new Error(`customer not found: ${CUSTOMER_EMAIL}`);
    const customerId = customers[0].id;

    console.log('==> issue coupon');
    const issue = await fetchJson('/api/v1/admin/coupons', {
      method: 'POST',
      headers: { Authorization: `Bearer ${adminToken}` },
      body: JSON.stringify({
        customerUserId: customerId,
        title: 'STG smoke 100',
        discountAmount: 100,
      }),
    });
    if (!issue.ok) throw new Error(`issue failed ${issue.status}: ${JSON.stringify(issue.body)}`);
    const couponId = issue.body.data.id;
    console.log(`coupon_id=${couponId} status=${issue.body.data.status}`);

    const customerToken = await loginCustomer();

    console.log('==> list available coupons');
    const list1 = await fetchJson('/api/v1/customer/coupons', {
      headers: { Authorization: `Bearer ${customerToken}` },
    });
    const available = (list1.body?.data || []).find((c) => c.id === couponId && c.status === 'AVAILABLE');
    if (!available) throw new Error(`coupon not listed as AVAILABLE: ${JSON.stringify(list1.body)}`);
    console.log('available_coupon_listed=ok');

    console.log('==> pricing');
    const pricingPayload = {
      bookingMode: 'STANDARD',
      serviceTypeCode: 'AIRPORT_PICKUP',
      vehicleTypeCode: 'SUV',
      vehicleCount: 1,
      originAirportIata: 'BKK',
      destinationLocationCode: 'PATTAYA',
      origin: { name: 'BKK', address: 'BKK', lat: 13.69, lng: 100.75 },
      destination: { name: 'Pattaya', address: 'Pattaya', lat: 12.92, lng: 100.88 },
      passengers: { adults: 2, children: 0, infants: 0 },
      luggage: {},
      options: {},
      transfer: { airportIata: 'BKK' },
    };
    const pricing = await fetchJson('/api/v1/bookings/pricing/calculate', {
      method: 'POST',
      body: JSON.stringify(pricingPayload),
    });
    if (!pricing.ok) throw new Error(`pricing failed: ${JSON.stringify(pricing.body)}`);
    const subtotal = Number(pricing.body.data.subtotal ?? pricing.body.data.totalAmount);
    if (!Number.isFinite(subtotal)) {
      throw new Error(`pricing subtotal missing: ${JSON.stringify(pricing.body)}`);
    }
    const expectedTotal = Math.max(subtotal - 100, 0);

    const pickup = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();
    console.log('==> create booking with coupon');
    const idempotencyKey = crypto.randomUUID();
    const booking = await fetchJson('/api/v1/bookings', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${customerToken}`,
        'Idempotency-Key': idempotencyKey,
      },
      body: JSON.stringify({
        ...pricingPayload,
        scheduledPickupAt: pickup,
        customer: { name: 'Deploy Test', phone: '+66812345678' },
        couponId,
      }),
    });
    if (!booking.ok) throw new Error(`booking failed ${booking.status}: ${JSON.stringify(booking.body)}`);
    const bookingId = booking.body.data.id;
    const totalAmount = Number(booking.body.data.totalAmount);
    if (totalAmount !== expectedTotal) {
      throw new Error(`total mismatch expected=${expectedTotal} actual=${totalAmount}`);
    }
    console.log(`booking_id=${bookingId} total_amount=${totalAmount} (subtotal=${subtotal}-100)`);

    console.log('==> coupon used');
    const list2 = await fetchJson('/api/v1/customer/coupons', {
      headers: { Authorization: `Bearer ${customerToken}` },
    });
    const used = (list2.body?.data || []).find((c) => c.id === couponId);
    if (!used || used.status !== 'USED') {
      throw new Error(`coupon not USED: ${JSON.stringify(list2.body)}`);
    }
    console.log(`coupon_status=USED bookingNumber=${used.bookingNumber || 'n/a'}`);

    console.log('==> reuse blocked');
    const reuse = await fetchJson('/api/v1/bookings', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${customerToken}`,
        'Idempotency-Key': crypto.randomUUID(),
      },
      body: JSON.stringify({
        ...pricingPayload,
        scheduledPickupAt: pickup,
        customer: { name: 'Deploy Test', phone: '+66812345678' },
        couponId,
      }),
    });
    if (reuse.ok) throw new Error('reuse should fail but succeeded');
    if (![400, 409].includes(reuse.status)) {
      throw new Error(`unexpected reuse status ${reuse.status}: ${JSON.stringify(reuse.body)}`);
    }
    console.log(`reuse_rejected=http_${reuse.status}`);

    console.log('==> DB total_amount + mileage basis');
    const [rows] = await conn.query('SELECT total_amount FROM bookings WHERE id = ? LIMIT 1', [bookingId]);
    const dbTotal = Number(rows[0]?.total_amount);
    const mileagePts = Math.floor(dbTotal / 20);
    if (dbTotal !== expectedTotal) {
      throw new Error(`db total mismatch expected=${expectedTotal} actual=${dbTotal}`);
    }
    console.log(`db_total_amount=${dbTotal} expected_mileage_on_settlement=${mileagePts} (total/20)`);

    console.log(`SMOKE_OK coupon_id=${couponId} booking_id=${bookingId}`);
  } finally {
    await conn.end();
  }
}

main().catch((err) => {
  console.error('SMOKE_FAIL', err.message);
  process.exit(1);
});

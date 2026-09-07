#!/usr/bin/env node
/**
 * STG coupon template smoke — runs inside tride-backend container.
 * Mints admin JWT internally; no admin password required.
 */
const fs = require('node:fs');
const path = require('node:path');
const mysql = require('mysql2/promise');
const jwt = require('jsonwebtoken');

const BASE_URL = process.env.TRIDE_BASE_URL || 'http://127.0.0.1:3000';
const CUSTOMER_EMAIL = process.env.TRIDE_CUSTOMER_EMAIL || 'mileage-deploy-test-20260831@example.com';
const CUSTOMER_PASSWORD = process.env.TRIDE_CUSTOMER_PASSWORD || 'DeployTest123!';
const IMAGE_PATH = process.env.TRIDE_COUPON_TEMPLATE_IMAGE || '/tmp/coupon-template.png';
const TEMPLATE_TITLE = process.env.TRIDE_COUPON_TEMPLATE_TITLE
  || `STG template smoke ${new Date().toISOString().slice(0, 19)}`;

function signAccessToken(user) {
  const secret = process.env.JWT_ACCESS_SECRET;
  if (!secret) throw new Error('JWT_ACCESS_SECRET missing');
  return jwt.sign(
    { sub: user.id, email: user.email, role: user.role, type: 'access' },
    secret,
    { expiresIn: '1h' },
  );
}

async function fetchJson(url, options = {}) {
  const res = await fetch(url, options);
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
  const { status, body } = await fetchJson(`${BASE_URL}/api/v1/auth/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: CUSTOMER_EMAIL, password: CUSTOMER_PASSWORD }),
  });
  if (!body?.data?.accessToken) {
    throw new Error(`customer login failed ${status}: ${body?.message || JSON.stringify(body)}`);
  }
  return body.data.accessToken;
}

async function main() {
  if (!fs.existsSync(IMAGE_PATH)) {
    throw new Error(`image not found: ${IMAGE_PATH}`);
  }

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
    const adminToken = signAccessToken(admins[0]);

    const [customers] = await conn.query(
      'SELECT id, email FROM users WHERE email = ? AND role = ? AND deleted_at IS NULL LIMIT 1',
      [CUSTOMER_EMAIL, 'CUSTOMER'],
    );
    if (!customers.length) throw new Error(`customer not found: ${CUSTOMER_EMAIL}`);
    const customerId = customers[0].id;

    console.log('==> recent customers');
    const recent = await fetchJson(`${BASE_URL}/api/v1/admin/customers/recent?limit=20`, {
      headers: { Authorization: `Bearer ${adminToken}` },
    });
    if (!recent.ok) throw new Error(`recent customers failed: ${JSON.stringify(recent.body)}`);
    const recentHit = (recent.body.data || []).find((row) => row.email === CUSTOMER_EMAIL);
    console.log(recentHit
      ? `recent_customer_found=id=${recentHit.id}`
      : `recent_customer_missing=fallback_search customer_id=${customerId}`);

    console.log('==> create template');
    const form = new FormData();
    form.append('title', TEMPLATE_TITLE);
    form.append('discountAmount', '100');
    const bytes = fs.readFileSync(IMAGE_PATH);
    form.append('file', new Blob([bytes], { type: 'image/png' }), path.basename(IMAGE_PATH));
    const create = await fetchJson(`${BASE_URL}/api/v1/admin/coupon-templates`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${adminToken}` },
      body: form,
    });
    if (!create.ok) throw new Error(`template create failed: ${JSON.stringify(create.body)}`);
    const templateId = create.body.data.id;
    console.log(`template_id=${templateId}`);

    console.log('==> issue from template');
    const issue = await fetchJson(`${BASE_URL}/api/v1/admin/coupons`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${adminToken}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({ customerUserId: customerId, templateId }),
    });
    if (!issue.ok) throw new Error(`issue failed: ${JSON.stringify(issue.body)}`);
    const couponId = issue.body.data.id;
    const imageUrl = issue.body.data.imageUrl;
    if (!imageUrl) throw new Error('issued coupon missing imageUrl');
    console.log(`coupon_id=${couponId} image_url=${imageUrl}`);

    const customerToken = await loginCustomer();

    console.log('==> customer coupon list');
    const list = await fetchJson(`${BASE_URL}/api/v1/customer/coupons`, {
      headers: { Authorization: `Bearer ${customerToken}` },
    });
    if (!list.ok) throw new Error(`list failed: ${JSON.stringify(list.body)}`);
    const issued = (list.body.data || []).find((row) => row.id === couponId);
    if (!issued?.imageUrl) throw new Error('customer list missing imageUrl for issued coupon');
    const legacyCount = (list.body.data || []).filter((row) => !row.imageUrl).length;
    console.log(`issued_image_url=${issued.imageUrl}`);
    console.log(`legacy_text_coupons=${legacyCount}`);

    console.log('==> fetch coupon image');
    const imageRes = await fetch(`${BASE_URL}${imageUrl}`, {
      headers: { Authorization: `Bearer ${customerToken}`, Accept: 'image/*' },
    });
    const imageBytes = Buffer.from(await imageRes.arrayBuffer());
    if (imageRes.status !== 200 || imageBytes.length < 100) {
      throw new Error(`image fetch failed status=${imageRes.status} bytes=${imageBytes.length}`);
    }
    console.log(`coupon_image_http=${imageRes.status} bytes=${imageBytes.length}`);

    console.log('==> deactivate template');
    const patch = await fetchJson(`${BASE_URL}/api/v1/admin/coupon-templates/${templateId}`, {
      method: 'PATCH',
      headers: {
        Authorization: `Bearer ${adminToken}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({ isActive: false }),
    });
    if (!patch.ok || patch.body.data.isActive !== false) {
      throw new Error(`deactivate failed: ${JSON.stringify(patch.body)}`);
    }

    const templates = await fetchJson(`${BASE_URL}/api/v1/admin/coupon-templates`, {
      headers: { Authorization: `Bearer ${adminToken}` },
    });
    const row = (templates.body.data || []).find((item) => item.id === templateId);
    if (!row || row.isActive !== false) throw new Error('template not inactive in admin list');
    const activeIds = (templates.body.data || []).filter((item) => item.isActive).map((item) => item.id);
    if (activeIds.includes(templateId)) throw new Error('inactive template still active');
    console.log(`template_inactive=ok active_template_count=${activeIds.length}`);

    console.log('==> image still available after template deactivation');
    const imageRes2 = await fetch(`${BASE_URL}${imageUrl}`, {
      headers: { Authorization: `Bearer ${customerToken}`, Accept: 'image/*' },
    });
    if (imageRes2.status !== 200) {
      throw new Error(`image after deactivate failed status=${imageRes2.status}`);
    }
    console.log(`coupon_image_after_deactivate=http_${imageRes2.status}`);

    console.log(`SMOKE_OK template_id=${templateId} coupon_id=${couponId} customer_id=${customerId}`);
  } finally {
    await conn.end();
  }
}

main().catch((err) => {
  console.error('SMOKE_FAIL', err.message);
  process.exit(1);
});

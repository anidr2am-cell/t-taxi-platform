#!/usr/bin/env node
/**
 * STG home banner smoke — runs inside tride-backend container.
 * Mints admin JWT internally; no admin password required.
 */
const fs = require('node:fs');
const path = require('path');
const mysql = require('mysql2/promise');
const jwt = require('jsonwebtoken');

const BASE_URL = process.env.TRIDE_BASE_URL || 'http://127.0.0.1:3000';
const IMAGE_PATH = process.env.TRIDE_HOME_BANNER_IMAGE || '/tmp/home-banner.png';

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

async function uploadBanner(adminToken, displayOrder) {
  const form = new FormData();
  form.append('displayOrder', String(displayOrder));
  const bytes = fs.readFileSync(IMAGE_PATH);
  form.append('file', new Blob([bytes], { type: 'image/png' }), path.basename(IMAGE_PATH));
  const create = await fetchJson(`${BASE_URL}/api/v1/admin/home-banners`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${adminToken}` },
    body: form,
  });
  if (!create.ok) throw new Error(`banner create failed: ${JSON.stringify(create.body)}`);
  return create.body.data;
}

async function main() {
  if (!fs.existsSync(IMAGE_PATH)) {
    throw new Error(`image not found: ${IMAGE_PATH}`);
  }

  console.log('==> public list (no auth)');
  const publicBefore = await fetchJson(`${BASE_URL}/api/v1/public/home-banners`);
  if (publicBefore.status !== 200) {
    throw new Error(`public list failed status=${publicBefore.status}`);
  }
  console.log(`public_before_count=${(publicBefore.body.data || []).length}`);

  const conn = await mysql.createConnection({
    host: process.env.DB_HOST || 'tride-db',
    port: Number(process.env.DB_PORT || 3306),
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
  });

  const createdIds = [];
  try {
    const [admins] = await conn.query(
      "SELECT id, email, role FROM users WHERE role IN ('ADMIN','SUPER_ADMIN') AND is_active = 1 AND deleted_at IS NULL ORDER BY id LIMIT 1",
    );
    if (!admins.length) throw new Error('no active admin user');
    const adminToken = signAccessToken(admins[0]);

    console.log('==> upload banner 1');
    const banner1 = await uploadBanner(adminToken, 0);
    createdIds.push(banner1.id);
    console.log(`banner1_id=${banner1.id} imageUrl=${banner1.imageUrl}`);

    console.log('==> upload banner 2');
    const banner2 = await uploadBanner(adminToken, 1);
    createdIds.push(banner2.id);
    console.log(`banner2_id=${banner2.id} imageUrl=${banner2.imageUrl}`);

    console.log('==> public list after upload');
    const publicAfter = await fetchJson(`${BASE_URL}/api/v1/public/home-banners`);
    const active = publicAfter.body.data || [];
    if (active.length < 2) throw new Error(`expected >=2 active banners, got ${active.length}`);
    console.log(`public_after_count=${active.length}`);

    console.log('==> public image fetch (no auth)');
    const imageUrl = active[0].imageUrl;
    const imageRes = await fetch(`${BASE_URL}${imageUrl}`, { headers: { Accept: 'image/*' } });
    const imageBytes = Buffer.from(await imageRes.arrayBuffer());
    if (imageRes.status !== 200 || imageBytes.length < 100) {
      throw new Error(`public image failed status=${imageRes.status} bytes=${imageBytes.length}`);
    }
    console.log(`public_image_http=${imageRes.status} bytes=${imageBytes.length}`);

    console.log('==> deactivate banner 2');
    const patch = await fetchJson(`${BASE_URL}/api/v1/admin/home-banners/${banner2.id}`, {
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

    const publicInactive = await fetchJson(`${BASE_URL}/api/v1/public/home-banners`);
    const ids = (publicInactive.body.data || []).map((row) => row.id);
    if (ids.includes(banner2.id)) throw new Error('inactive banner still in public list');
    if (!ids.includes(banner1.id)) throw new Error('active banner missing from public list');
    console.log(`public_after_deactivate_count=${ids.length} inactive_hidden=ok`);

    console.log('==> cleanup created banners');
    for (const id of createdIds) {
      const del = await fetchJson(`${BASE_URL}/api/v1/admin/home-banners/${id}`, {
        method: 'DELETE',
        headers: { Authorization: `Bearer ${adminToken}` },
      });
      if (!del.ok && del.status !== 404) {
        throw new Error(`delete banner ${id} failed: ${JSON.stringify(del.body)}`);
      }
    }

    console.log(`SMOKE_OK banner1_id=${banner1.id} banner2_id=${banner2.id}`);
  } finally {
    await conn.end();
  }
}

main().catch((err) => {
  console.error('SMOKE_FAIL', err.message);
  process.exit(1);
});

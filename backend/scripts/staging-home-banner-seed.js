#!/usr/bin/env node
const fs = require('fs');
const mysql = require('mysql2/promise');
const jwt = require('jsonwebtoken');

(async () => {
  const imagePath = process.env.TRIDE_HOME_BANNER_IMAGE || '/tmp/home-banner-seed.png';
  if (!fs.existsSync(imagePath)) throw new Error(`missing ${imagePath}`);
  const conn = await mysql.createConnection({
    host: process.env.DB_HOST,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
  });
  const [admins] = await conn.query(
    "SELECT id, email, role FROM users WHERE role IN ('ADMIN','SUPER_ADMIN') AND is_active = 1 AND deleted_at IS NULL ORDER BY id LIMIT 1",
  );
  const token = jwt.sign(
    { sub: admins[0].id, email: admins[0].email, role: admins[0].role, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
  for (const order of [0, 1]) {
    const form = new FormData();
    form.append('displayOrder', String(order));
    form.append('file', new Blob([fs.readFileSync(imagePath)], { type: 'image/png' }), 'banner.png');
    const res = await fetch('http://127.0.0.1:3000/api/v1/admin/home-banners', {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}` },
      body: form,
    });
    const body = await res.json();
    console.log(`seed order=${order} id=${body?.data?.id} ok=${res.ok}`);
  }
  await conn.end();
})().catch((err) => {
  console.error(err);
  process.exit(1);
});

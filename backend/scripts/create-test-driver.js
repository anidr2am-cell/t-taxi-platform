#!/usr/bin/env node
/**
 * Local development only — create or update a DRIVER test account.
 *
 * Examples:
 *   npm run create-test-driver -- --db-port=3308 --email=driver.local@ttaxi.dev --name="Local Driver" --phone=+66812345678
 *   npm run create-test-driver
 *
 * Password: pass --password=... or enter interactively (hidden when TTY).
 * Do not use in production migrations or committed credentials.
 */
const path = require('path');

function parseArgs(argv) {
  const args = {};
  for (const arg of argv) {
    if (!arg.startsWith('--')) continue;
    const body = arg.slice(2);
    const eq = body.indexOf('=');
    if (eq === -1) {
      args[body] = true;
    } else {
      args[body.slice(0, eq)] = body.slice(eq + 1);
    }
  }
  return args;
}

const cliArgs = parseArgs(process.argv.slice(2));

require('dotenv').config({
  path: path.join(__dirname, '../.env'),
  override: true,
});

if (cliArgs['db-port']) process.env.DB_PORT = String(cliArgs['db-port']);
if (cliArgs['db-host']) process.env.DB_HOST = String(cliArgs['db-host']);
if (cliArgs['db-user']) process.env.DB_USER = String(cliArgs['db-user']);
if (cliArgs['db-name']) process.env.DB_NAME = String(cliArgs['db-name']);
if (cliArgs['db-password'] !== undefined) process.env.DB_PASSWORD = String(cliArgs['db-password']);

const bcrypt = require('bcryptjs');
const readline = require('readline');
const database = require('../src/config/database');
const ROLES = require('../src/constants/roles');

const BCRYPT_ROUNDS = 12;

function readLine(question) {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer.trim());
    });
  });
}

function readPassword(prompt) {
  if (!process.stdin.isTTY) {
    return Promise.reject(
      new Error('Interactive password entry requires a TTY. Use --password=... or set stdin.'),
    );
  }

  return new Promise((resolve, reject) => {
    const stdin = process.stdin;
    const stdout = process.stdout;

    stdout.write(prompt);
    stdin.resume();
    stdin.setRawMode(true);
    stdin.setEncoding('utf8');

    let password = '';

    const onData = (ch) => {
      if (ch === '\n' || ch === '\r' || ch === '\u0004') {
        stdin.setRawMode(false);
        stdin.pause();
        stdin.removeListener('data', onData);
        stdout.write('\n');
        resolve(password);
        return;
      }

      if (ch === '\u0003') {
        stdin.setRawMode(false);
        stdin.pause();
        stdin.removeListener('data', onData);
        stdout.write('\n');
        reject(new Error('Cancelled'));
        return;
      }

      if (ch === '\u007f' || ch === '\b') {
        password = password.slice(0, -1);
        return;
      }

      password += ch;
    };

    stdin.on('data', onData);
  });
}

async function resolveInputs(args) {
  let email = args.email;
  let name = args.name;
  let phone = args.phone;
  let password = args.password;

  if (!email) email = await readLine('Email: ');
  if (!name) name = await readLine('Driver name: ');
  if (!phone) phone = await readLine('Phone: ');
  if (!password) password = await readPassword('Password (hidden): ');

  email = String(email).trim().toLowerCase();
  name = String(name).trim();
  phone = String(phone).trim();
  password = String(password);

  if (!email || !name || !phone || !password) {
    throw new Error('email, name, phone, and password are required');
  }

  return { email, name, phone, password };
}

async function upsertTestDriver({ email, name, phone, password }) {
  const passwordHash = await bcrypt.hash(password, BCRYPT_ROUNDS);
  const conn = await database.pool.getConnection();

  try {
    await conn.beginTransaction();

    const [existingUsers] = await conn.query(
      `
        SELECT id
        FROM users
        WHERE email = ? AND deleted_at IS NULL
        LIMIT 1
      `,
      [email],
    );

    let userId;
    let action;

    if (existingUsers.length) {
      userId = existingUsers[0].id;
      await conn.query(
        `
          UPDATE users
          SET password_hash = ?,
              role = ?,
              phone = ?,
              is_active = 1,
              updated_at = CURRENT_TIMESTAMP
          WHERE id = ?
        `,
        [passwordHash, ROLES.DRIVER, phone, userId],
      );
      action = 'updated';
    } else {
      const [userResult] = await conn.query(
        `
          INSERT INTO users (
            email, password_hash, role, phone, locale, is_active
          ) VALUES (?, ?, ?, ?, 'en', 1)
        `,
        [email, passwordHash, ROLES.DRIVER, phone],
      );
      userId = userResult.insertId;
      action = 'created';
    }

    const [profiles] = await conn.query(
      `
        SELECT id
        FROM user_profiles
        WHERE user_id = ? AND deleted_at IS NULL
        LIMIT 1
      `,
      [userId],
    );

    if (profiles.length) {
      await conn.query(
        `
          UPDATE user_profiles
          SET display_name = ?, updated_at = CURRENT_TIMESTAMP
          WHERE user_id = ?
        `,
        [name, userId],
      );
    } else {
      await conn.query(
        `INSERT INTO user_profiles (user_id, display_name) VALUES (?, ?)`,
        [userId, name],
      );
    }

    const [drivers] = await conn.query(
      `
        SELECT id
        FROM drivers
        WHERE user_id = ? AND deleted_at IS NULL
        LIMIT 1
      `,
      [userId],
    );

    let driverId;

    if (drivers.length) {
      driverId = drivers[0].id;
      await conn.query(
        `
          UPDATE drivers
          SET name = ?,
              phone = ?,
              is_active = 1,
              updated_at = CURRENT_TIMESTAMP
          WHERE id = ?
        `,
        [name, phone, driverId],
      );
    } else {
      const [driverResult] = await conn.query(
        `
          INSERT INTO drivers (
            user_id, name, phone, status, is_active, is_online
          ) VALUES (?, ?, ?, 'OFFLINE', 1, 0)
        `,
        [userId, name, phone],
      );
      driverId = driverResult.insertId;
    }

    await conn.commit();
    return { action, email, driverId, userId };
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}

async function main() {
  const inputs = await resolveInputs(cliArgs);
  const result = await upsertTestDriver(inputs);

  console.log(`Result: ${result.action}`);
  console.log(`Email: ${result.email}`);
  console.log(`Driver ID: ${result.driverId}`);
}

main()
  .catch((err) => {
    console.error(`Failed: ${err.message}`);
    process.exit(1);
  })
  .finally(async () => {
    await database.pool.end();
  });

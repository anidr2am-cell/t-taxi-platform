/**
 * config/database.js — MySQL connection pool (skeleton)
 *
 * Repository 레이어가 이 pool을 사용합니다.
 * 실제 SQL은 repositories/ 에서만 작성합니다.
 */
const mysql = require('mysql2/promise');
const env = require('./env');
const logger = require('../utils/logger');

const db = env.database;

const pool = mysql.createPool({
  host: db.host,
  port: db.port,
  user: db.user,
  password: db.password,
  database: db.name,
  waitForConnections: true,
  connectionLimit: db.connectionLimit,
  charset: 'utf8mb4',
  timezone: '+00:00',
});

pool.on('connection', () => {
  logger.debug('MySQL pool: new connection');
});

/**
 * Health check helper — used by /health endpoint later
 */
async function ping() {
  const conn = await pool.getConnection();
  try {
    await conn.ping();
    return true;
  } finally {
    conn.release();
  }
}

module.exports = {
  pool,
  ping,
};

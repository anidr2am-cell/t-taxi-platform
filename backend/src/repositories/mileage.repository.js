const database = require('../config/database');

const MILEAGE_TYPES = {
  ACCRUE: 'ACCRUE',
  REVERSAL: 'REVERSAL',
};

class MileageRepository {
  constructor(pool = database.pool) {
    this.pool = pool;
  }

  async findBookingForAccrual(conn, bookingId) {
    const [rows] = await conn.query(
      `
        SELECT
          b.id,
          b.customer_user_id,
          b.total_amount
        FROM bookings b
        WHERE b.id = ?
          AND b.deleted_at IS NULL
        LIMIT 1
      `,
      [bookingId],
    );
    return rows[0] || null;
  }

  async findTransactionByBookingIdAndType(conn, bookingId, type) {
    const [rows] = await conn.query(
      `
        SELECT
          id,
          user_id,
          booking_id,
          type,
          amount,
          balance_after,
          created_at
        FROM mileage_transactions
        WHERE booking_id = ?
          AND type = ?
        LIMIT 1
      `,
      [bookingId, type],
    );
    return rows[0] || null;
  }

  async insertTransaction(conn, { userId, bookingId, type, amount, balanceAfter }) {
    const [result] = await conn.query(
      `
        INSERT INTO mileage_transactions (
          user_id,
          booking_id,
          type,
          amount,
          balance_after
        ) VALUES (?, ?, ?, ?, ?)
      `,
      [userId, bookingId, type, amount, balanceAfter],
    );
    return result.insertId;
  }

  async updateTransactionBalanceAfter(conn, transactionId, balanceAfter) {
    await conn.query(
      `
        UPDATE mileage_transactions
        SET balance_after = ?
        WHERE id = ?
      `,
      [balanceAfter, transactionId],
    );
  }

  async getAccountForUpdate(conn, userId) {
    const [rows] = await conn.query(
      `
        SELECT user_id, balance, updated_at
        FROM customer_mileage_accounts
        WHERE user_id = ?
        FOR UPDATE
      `,
      [userId],
    );
    return rows[0] || null;
  }

  async createAccount(conn, userId, balance = 0) {
    await conn.query(
      `
        INSERT INTO customer_mileage_accounts (user_id, balance)
        VALUES (?, ?)
      `,
      [userId, balance],
    );
  }

  async updateAccountBalance(conn, userId, balance) {
    await conn.query(
      `
        UPDATE customer_mileage_accounts
        SET balance = ?, updated_at = CURRENT_TIMESTAMP
        WHERE user_id = ?
      `,
      [balance, userId],
    );
  }

  async getBalance(userId) {
    const [rows] = await this.pool.query(
      `
        SELECT balance
        FROM customer_mileage_accounts
        WHERE user_id = ?
        LIMIT 1
      `,
      [userId],
    );
    return rows[0]?.balance ?? 0;
  }

  async getTransactionHistory(userId, { page = 1, limit = 20 } = {}) {
    const safePage = Math.max(1, Number(page) || 1);
    const safeLimit = Math.min(100, Math.max(1, Number(limit) || 20));
    const offset = (safePage - 1) * safeLimit;

    const [countRows] = await this.pool.query(
      `
        SELECT COUNT(*) AS total
        FROM mileage_transactions
        WHERE user_id = ?
      `,
      [userId],
    );
    const total = Number(countRows[0]?.total ?? 0);

    const [rows] = await this.pool.query(
      `
        SELECT
          id,
          user_id,
          booking_id,
          type,
          amount,
          balance_after,
          created_at
        FROM mileage_transactions
        WHERE user_id = ?
        ORDER BY created_at DESC, id DESC
        LIMIT ? OFFSET ?
      `,
      [userId, safeLimit, offset],
    );

    return {
      items: rows,
      page: safePage,
      limit: safeLimit,
      total,
    };
  }
}

module.exports = MileageRepository;
module.exports.MILEAGE_TYPES = MILEAGE_TYPES;

const logger = require('../utils/logger');
const { MILEAGE_TYPES } = require('../repositories/mileage.repository');

const ACCRUAL_RATE = 0.05;

function isPoolConnection(connOrPool) {
  return connOrPool && typeof connOrPool.getConnection === 'function';
}

function computeAccrualAmount(totalAmount) {
  const normalizedTotal = Number(totalAmount);
  if (!Number.isFinite(normalizedTotal) || normalizedTotal <= 0) {
    return 0;
  }
  return Math.floor(normalizedTotal * ACCRUAL_RATE);
}

class MileageService {
  constructor(pool, mileageRepository, bookingRepository) {
    this.pool = pool;
    this.mileageRepository = mileageRepository;
    this.bookingRepository = bookingRepository;
  }

  async accrueForBooking(bookingId, connOrPool = null) {
    const executor = connOrPool || this.pool;
    const ownConnection = isPoolConnection(executor);
    const conn = ownConnection ? await executor.getConnection() : executor;

    try {
      if (ownConnection) {
        await conn.beginTransaction();
      }

      const booking = await this.mileageRepository.findBookingForAccrual(conn, bookingId);
      if (!booking) {
        if (ownConnection) await conn.rollback();
        return { skipped: true, reason: 'BOOKING_NOT_FOUND' };
      }

      if (!booking.customer_user_id) {
        logger.info('Mileage accrual skipped for guest booking', { bookingId });
        if (ownConnection) await conn.rollback();
        return { skipped: true, reason: 'GUEST_BOOKING' };
      }

      const existing = await this.mileageRepository.findTransactionByBookingIdAndType(
        conn,
        bookingId,
        MILEAGE_TYPES.ACCRUE,
      );
      if (existing) {
        if (ownConnection) await conn.rollback();
        return {
          skipped: true,
          reason: 'ALREADY_ACCRUED',
          idempotent: true,
          amount: existing.amount,
          balanceAfter: existing.balance_after,
        };
      }

      const amount = computeAccrualAmount(booking.total_amount);
      if (amount <= 0) {
        if (ownConnection) await conn.rollback();
        return { skipped: true, reason: 'ZERO_AMOUNT' };
      }

      const userId = booking.customer_user_id;
      let account = await this.mileageRepository.getAccountForUpdate(conn, userId);
      if (!account) {
        await this.mileageRepository.createAccount(conn, userId, 0);
        account = { user_id: userId, balance: 0 };
      }

      let transactionId;
      try {
        transactionId = await this.mileageRepository.insertTransaction(conn, {
          userId,
          bookingId,
          type: MILEAGE_TYPES.ACCRUE,
          amount,
          balanceAfter: 0,
        });
      } catch (err) {
        if (err.code === 'ER_DUP_ENTRY') {
          if (ownConnection) await conn.rollback();
          return { skipped: true, reason: 'ALREADY_ACCRUED', idempotent: true };
        }
        throw err;
      }

      const balanceAfter = Number(account.balance) + amount;
      await this.mileageRepository.updateAccountBalance(conn, userId, balanceAfter);
      await this.mileageRepository.updateTransactionBalanceAfter(conn, transactionId, balanceAfter);

      if (ownConnection) {
        await conn.commit();
      }

      return {
        accrued: true,
        amount,
        balanceAfter,
        userId,
        bookingId,
      };
    } catch (err) {
      if (ownConnection) {
        await conn.rollback();
      }
      throw err;
    } finally {
      if (ownConnection) {
        conn.release();
      }
    }
  }

  async reverseForBooking(bookingId, connOrPool = null) {
    const executor = connOrPool || this.pool;
    const ownConnection = isPoolConnection(executor);
    const conn = ownConnection ? await executor.getConnection() : executor;

    try {
      if (ownConnection) {
        await conn.beginTransaction();
      }

      const accrueTxn = await this.mileageRepository.findTransactionByBookingIdAndType(
        conn,
        bookingId,
        MILEAGE_TYPES.ACCRUE,
      );
      if (!accrueTxn) {
        if (ownConnection) await conn.rollback();
        return { skipped: true, reason: 'NO_ACCRUE' };
      }

      const existingReversal = await this.mileageRepository.findTransactionByBookingIdAndType(
        conn,
        bookingId,
        MILEAGE_TYPES.REVERSAL,
      );
      if (existingReversal) {
        if (ownConnection) await conn.rollback();
        return {
          skipped: true,
          reason: 'ALREADY_REVERSED',
          idempotent: true,
          amount: existingReversal.amount,
          balanceAfter: existingReversal.balance_after,
        };
      }

      const userId = accrueTxn.user_id;
      const reversalAmount = -Math.abs(Number(accrueTxn.amount));

      let account = await this.mileageRepository.getAccountForUpdate(conn, userId);
      if (!account) {
        await this.mileageRepository.createAccount(conn, userId, 0);
        account = { user_id: userId, balance: 0 };
      }

      let transactionId;
      try {
        transactionId = await this.mileageRepository.insertTransaction(conn, {
          userId,
          bookingId,
          type: MILEAGE_TYPES.REVERSAL,
          amount: reversalAmount,
          balanceAfter: 0,
        });
      } catch (err) {
        if (err.code === 'ER_DUP_ENTRY') {
          if (ownConnection) await conn.rollback();
          return { skipped: true, reason: 'ALREADY_REVERSED', idempotent: true };
        }
        throw err;
      }

      const balanceAfter = Math.max(0, Number(account.balance) + reversalAmount);
      await this.mileageRepository.updateAccountBalance(conn, userId, balanceAfter);
      await this.mileageRepository.updateTransactionBalanceAfter(conn, transactionId, balanceAfter);

      if (ownConnection) {
        await conn.commit();
      }

      return {
        reversed: true,
        amount: reversalAmount,
        balanceAfter,
        userId,
        bookingId,
      };
    } catch (err) {
      if (ownConnection) {
        await conn.rollback();
      }
      throw err;
    } finally {
      if (ownConnection) {
        conn.release();
      }
    }
  }

  async getBalance(userId) {
    const balance = await this.mileageRepository.getBalance(userId);
    return Number(balance);
  }

  async getTransactionHistory(userId, options = {}) {
    return this.mileageRepository.getTransactionHistory(userId, options);
  }
}

module.exports = MileageService;
module.exports.computeAccrualAmount = computeAccrualAmount;
module.exports.ACCRUAL_RATE = ACCRUAL_RATE;

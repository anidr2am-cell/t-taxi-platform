const logger = require('../utils/logger');

class BookingIdempotencyCleanupWorker {
  constructor({
    pool,
    bookingIdempotencyRepository,
    settlementReceiptIdempotencyRepository = null,
    config,
    nowFn = () => Date.now(),
  }) {
    this.pool = pool;
    this.bookingIdempotencyRepository = bookingIdempotencyRepository;
    this.settlementReceiptIdempotencyRepository = settlementReceiptIdempotencyRepository;
    this.config = config;
    this.nowFn = nowFn;
  }

  async runCycle() {
    const startedAt = this.nowFn();
    const conn = await this.pool.getConnection();
    try {
      const bookingDeleted = await this.bookingIdempotencyRepository.deleteExpiredBatch(
        conn,
        this.config.batchSize,
      );
      const receiptDeleted = this.settlementReceiptIdempotencyRepository
        ? await this.settlementReceiptIdempotencyRepository.deleteExpiredBatch(
          conn,
          this.config.batchSize,
        )
        : 0;
      return {
        deleted: bookingDeleted + receiptDeleted,
        bookingDeleted,
        receiptDeleted,
        durationMs: this.nowFn() - startedAt,
      };
    } catch (err) {
      logger.warn('Booking idempotency cleanup worker cycle failed', { error: err.message });
      return {
        deleted: 0,
        failed: 1,
        durationMs: this.nowFn() - startedAt,
      };
    } finally {
      conn.release();
    }
  }
}

module.exports = BookingIdempotencyCleanupWorker;

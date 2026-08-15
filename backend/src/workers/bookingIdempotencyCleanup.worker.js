const logger = require('../utils/logger');

class BookingIdempotencyCleanupWorker {
  constructor({
    pool,
    bookingIdempotencyRepository,
    config,
    nowFn = () => Date.now(),
  }) {
    this.pool = pool;
    this.bookingIdempotencyRepository = bookingIdempotencyRepository;
    this.config = config;
    this.nowFn = nowFn;
  }

  async runCycle() {
    const startedAt = this.nowFn();
    const conn = await this.pool.getConnection();
    try {
      const deleted = await this.bookingIdempotencyRepository.deleteExpiredBatch(
        conn,
        this.config.batchSize,
      );
      return {
        deleted,
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

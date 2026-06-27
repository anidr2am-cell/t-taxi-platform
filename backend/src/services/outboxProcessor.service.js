const logger = require('../utils/logger');
const { OUTBOX_STATUS } = require('../constants/outboxStatus');

const DEFAULT_BATCH_SIZE = 50;

class OutboxProcessor {
  constructor(outboxRepository, notificationServiceResolver, batchSize = DEFAULT_BATCH_SIZE) {
    this.outboxRepository = outboxRepository;
    this.notificationServiceResolver = notificationServiceResolver;
    this.batchSize = batchSize;
  }

  getNotificationService() {
    return this.notificationServiceResolver();
  }

  async processClaimedRow(row) {
    if (!row || row.status === OUTBOX_STATUS.COMPLETED) return;

    try {
      await this.getNotificationService().handleDomainEvent(row.event_type, row.payload ?? {});
      await this.outboxRepository.markCompleted(row.id);
    } catch (err) {
      await this.outboxRepository.markFailed(row.id, err.message);
      logger.warn('Outbox notification processing failed', {
        outboxId: row.id,
        eventType: row.event_type,
        error: err.message,
      });
    }
  }

  async dispatchOutboxIds(outboxIds = []) {
    for (const id of outboxIds) {
      if (!id) continue;
      try {
        const row = await this.outboxRepository.claimById(id);
        if (row) {
          await this.processClaimedRow(row);
        }
      } catch (err) {
        logger.warn('Post-commit outbox dispatch failed', {
          outboxId: id,
          error: err.message,
        });
      }
    }
  }

  async processPendingBatch(limit = this.batchSize) {
    const boundedLimit = Math.min(Math.max(Number(limit) || this.batchSize, 1), this.batchSize);
    const conn = await this.outboxRepository.pool.getConnection();
    let rows = [];

    try {
      await conn.beginTransaction();
      rows = await this.outboxRepository.claimPendingBatch(conn, boundedLimit);
      await conn.commit();
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }

    for (const row of rows) {
      await this.processClaimedRow(row);
    }

    return rows.length;
  }

  async recoverOnStartup() {
    try {
      const processed = await this.processPendingBatch(this.batchSize);
      if (processed > 0) {
        logger.info('Outbox startup recovery processed notification events', { processed });
      }
    } catch (err) {
      logger.warn('Outbox startup recovery failed', { error: err.message });
    }
  }
}

module.exports = OutboxProcessor;

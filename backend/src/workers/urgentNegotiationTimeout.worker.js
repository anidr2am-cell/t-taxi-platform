const logger = require('../utils/logger');

class UrgentNegotiationTimeoutWorker {
  constructor({
    urgentNegotiationService,
    config,
    nowFn = () => Date.now(),
  }) {
    this.urgentNegotiationService = urgentNegotiationService;
    this.config = config;
    this.nowFn = nowFn;
  }

  async runCycle() {
    const startedAt = this.nowFn();
    try {
      const summary = await this.urgentNegotiationService.processExpiredNegotiations({
        batchSize: this.config.batchSize,
        nowMs: startedAt,
      });
      return summary;
    } catch (err) {
      logger.warn('Urgent negotiation timeout worker cycle failed', { error: err.message });
      return {
        lockedSelected: 0,
        lockedProcessed: 0,
        lockedFailed: 1,
        customerSelected: 0,
        customerProcessed: 0,
        customerFailed: 0,
        durationMs: this.nowFn() - startedAt,
      };
    }
  }
}

module.exports = UrgentNegotiationTimeoutWorker;

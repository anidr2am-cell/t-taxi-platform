const logger = require('../utils/logger');

class UrgentNegotiationSchedulerService {
  constructor(worker, config, nowFn = () => new Date()) {
    this.worker = worker;
    this.config = config;
    this.nowFn = nowFn;
    this.timer = null;
    this.running = false;
    this.started = false;
    this.lastCycleStartedAt = null;
    this.lastCycleCompletedAt = null;
    this.lastCycle = null;
    this.nextExpectedRunAt = null;
  }

  start() {
    if (this.started) return;
    this.started = true;
    logger.info('Urgent negotiation timeout worker startup', {
      enabled: this.config.enabled,
      intervalMs: this.config.intervalMs,
      batchSize: this.config.batchSize,
    });
    if (!this.config.enabled) return;
    this.scheduleNext();
  }

  scheduleNext() {
    if (!this.config.enabled || this.timer) return;
    this.nextExpectedRunAt = new Date(Date.now() + this.config.intervalMs).toISOString();
    this.timer = setTimeout(async () => {
      this.timer = null;
      await this.runCycle();
      this.scheduleNext();
    }, this.config.intervalMs);
    if (this.timer.unref) this.timer.unref();
  }

  async runCycle() {
    if (this.running) {
      const skipped = {
        lockedSelected: 0,
        lockedProcessed: 0,
        lockedFailed: 0,
        customerSelected: 0,
        customerProcessed: 0,
        customerFailed: 0,
        durationMs: 0,
        skippedReason: 'ALREADY_RUNNING',
      };
      this.lastCycle = skipped;
      return skipped;
    }
    this.running = true;
    this.lastCycleStartedAt = this.nowFn().toISOString();
    try {
      const summary = await this.worker.runCycle();
      this.lastCycle = summary;
      return summary;
    } catch (err) {
      const failed = {
        lockedSelected: 0,
        lockedProcessed: 0,
        lockedFailed: 1,
        customerSelected: 0,
        customerProcessed: 0,
        customerFailed: 0,
        durationMs: 0,
      };
      this.lastCycle = failed;
      logger.warn('Urgent negotiation timeout worker cycle failed', { error: err.message });
      return failed;
    } finally {
      this.running = false;
      this.lastCycleCompletedAt = this.nowFn().toISOString();
    }
  }

  async runNow() {
    return this.runCycle();
  }

  stop() {
    if (this.timer) {
      clearTimeout(this.timer);
      this.timer = null;
    }
    this.started = false;
    this.nextExpectedRunAt = null;
    logger.info('Urgent negotiation timeout worker stopped');
  }

  getStatus() {
    return {
      enabled: this.config.enabled,
      running: this.running,
      intervalMs: this.config.intervalMs,
      batchSize: this.config.batchSize,
      lastCycleStartedAt: this.lastCycleStartedAt,
      lastCycleCompletedAt: this.lastCycleCompletedAt,
      lastCycle: this.lastCycle,
      nextExpectedRunAt: this.nextExpectedRunAt,
    };
  }
}

module.exports = UrgentNegotiationSchedulerService;

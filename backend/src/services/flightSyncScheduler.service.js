const logger = require('../utils/logger');

class FlightSyncSchedulerService {
  constructor(worker, config, providerConfiguredFn = () => false, nowFn = () => new Date()) {
    this.worker = worker;
    this.config = config;
    this.providerConfiguredFn = providerConfiguredFn;
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
    logger.info('Flight sync worker startup', {
      enabled: this.config.enabled,
      intervalMs: this.config.intervalMs,
      batchSize: this.config.batchSize,
      providerConfigured: this.providerConfiguredFn(),
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
        selected: 0,
        succeeded: 0,
        skipped: 1,
        failed: 0,
        rateLimited: false,
        configMissing: false,
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
        selected: 0,
        succeeded: 0,
        skipped: 0,
        failed: 1,
        rateLimited: false,
        configMissing: false,
        durationMs: 0,
      };
      this.lastCycle = failed;
      logger.warn('Flight sync worker cycle failed', { error: err.message });
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
    logger.info('Flight sync worker stopped');
  }

  getStatus() {
    return {
      enabled: this.config.enabled,
      running: this.running,
      providerConfigured: this.providerConfiguredFn(),
      intervalMs: this.config.intervalMs,
      batchSize: this.config.batchSize,
      lastCycleStartedAt: this.lastCycleStartedAt,
      lastCycleCompletedAt: this.lastCycleCompletedAt,
      lastCycle: this.lastCycle,
      nextExpectedRunAt: this.nextExpectedRunAt,
    };
  }
}

module.exports = FlightSyncSchedulerService;

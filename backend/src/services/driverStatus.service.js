const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const logger = require('../utils/logger');

const DRIVER_STATUS = {
  AVAILABLE: 'AVAILABLE',
  OFFLINE: 'OFFLINE',
  SUSPENDED: 'SUSPENDED',
};

const CALL_ELIGIBILITY = {
  READY: 'READY',
  OFFLINE: 'OFFLINE',
  ACTIVE_TRIP: 'ACTIVE_TRIP',
  UNPAID_SETTLEMENT: 'UNPAID_SETTLEMENT',
  ACCOUNT_UNDER_REVIEW: 'ACCOUNT_UNDER_REVIEW',
  ACCOUNT_RESTRICTED: 'ACCOUNT_RESTRICTED',
  DRIVER_APPROVAL_PENDING: 'DRIVER_APPROVAL_PENDING',
  VEHICLE_REVIEW_REQUIRED: 'VEHICLE_REVIEW_REQUIRED',
  UNKNOWN_RESTRICTION: 'UNKNOWN_RESTRICTION',
};

class DriverStatusService {
  constructor(pool, driverRepository, commissionSettlementService = null) {
    this.pool = pool;
    this.driverRepository = driverRepository;
    this.commissionSettlementService = commissionSettlementService;
  }

  async buildCallEligibility(driver, hasActiveJob = null) {
    const activeJob = hasActiveJob ?? Number(driver.active_job_count ?? 0) > 0;
    const online = Boolean(driver.is_online) && driver.status !== DRIVER_STATUS.OFFLINE;
    const active = Boolean(driver.is_active) && Boolean(driver.user_is_active ?? 1);

    if (!active || driver.status === DRIVER_STATUS.SUSPENDED) {
      return {
        canReceiveCalls: false,
        reasonCode: CALL_ELIGIBILITY.ACCOUNT_RESTRICTED,
      };
    }

    if (['UNDER_REVIEW', 'REVIEWING', 'ACCOUNT_UNDER_REVIEW'].includes(driver.status)) {
      return {
        canReceiveCalls: false,
        reasonCode: CALL_ELIGIBILITY.ACCOUNT_UNDER_REVIEW,
      };
    }

    if (['PENDING', 'PENDING_APPROVAL', 'APPROVAL_PENDING'].includes(driver.status)) {
      return {
        canReceiveCalls: false,
        reasonCode: CALL_ELIGIBILITY.DRIVER_APPROVAL_PENDING,
      };
    }

    if (Number(driver.active_vehicle_count ?? 1) <= 0) {
      return {
        canReceiveCalls: false,
        reasonCode: CALL_ELIGIBILITY.VEHICLE_REVIEW_REQUIRED,
      };
    }

    if (this.commissionSettlementService
      && await this.commissionSettlementService.driverHasBlockingSettlement(driver.id)) {
      return {
        canReceiveCalls: false,
        reasonCode: CALL_ELIGIBILITY.UNPAID_SETTLEMENT,
      };
    }

    if (!online || driver.status === DRIVER_STATUS.OFFLINE) {
      return {
        canReceiveCalls: false,
        reasonCode: CALL_ELIGIBILITY.OFFLINE,
      };
    }

    if (driver.status !== DRIVER_STATUS.AVAILABLE) {
      return {
        canReceiveCalls: false,
        reasonCode: CALL_ELIGIBILITY.UNKNOWN_RESTRICTION,
      };
    }

    return {
      canReceiveCalls: true,
      reasonCode: CALL_ELIGIBILITY.READY,
    };
  }

  async mapStatus(driver, hasActiveJob = null) {
    const activeJob = hasActiveJob ?? Number(driver.active_job_count ?? 0) > 0;
    return {
      driverId: Number(driver.id),
      active: Boolean(driver.is_active) && Boolean(driver.user_is_active ?? 1),
      online: Boolean(driver.is_online) && driver.status !== DRIVER_STATUS.OFFLINE,
      status: driver.status,
      hasActiveJob: activeJob,
      lastSeenAt: driver.last_seen_at ?? null,
      callEligibility: await this.buildCallEligibility(driver, activeJob),
    };
  }

  assertCanGoOnline(driver) {
    if (!driver || !driver.is_active || driver.user_is_active === 0) {
      throw new AppError('Driver not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.DRIVER_NOT_FOUND,
      });
    }
    if (driver.status === DRIVER_STATUS.SUSPENDED) {
      throw new AppError('Driver is suspended', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.DRIVER_NOT_ELIGIBLE,
      });
    }
  }

  async assertSettlementEligible(driverId) {
    if (!this.commissionSettlementService) return;
    const blocked = await this.commissionSettlementService.driverHasBlockingSettlement(driverId);
    if (blocked) {
      throw new AppError('This driver cannot receive a new job until the previous settlement is confirmed.', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.DRIVER_NOT_ELIGIBLE,
      });
    }
  }

  async getStatus(driverUserId) {
    const driver = await this.driverRepository.findByUserId(driverUserId);
    if (!driver) {
      throw new AppError('Driver not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.DRIVER_NOT_FOUND,
      });
    }
    return this.mapStatus(driver);
  }

  async goOnline(driverUserId) {
    const conn = await this.pool.getConnection();
    let driver;
    let hasActiveJob = false;
    try {
      await conn.beginTransaction();
      driver = await this.driverRepository.findByUserIdForUpdate(conn, driverUserId);
      this.assertCanGoOnline(driver);
      await this.assertSettlementEligible(driver.id);
      hasActiveJob = await this.driverRepository.hasActiveJob(conn, driver.id);
      await this.driverRepository.updateOnlineState(conn, driver.id, {
        isOnline: true,
        status: DRIVER_STATUS.AVAILABLE,
      });
      await conn.commit();
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }

    logger.info('Driver went online', { driverId: driver.id });
    return this.getStatus(driverUserId).then((status) => ({ ...status, hasActiveJob }));
  }

  async goOffline(driverUserId, { allowActiveJob = false } = {}) {
    const conn = await this.pool.getConnection();
    let driver;
    let hasActiveJob = false;
    try {
      await conn.beginTransaction();
      driver = await this.driverRepository.findByUserIdForUpdate(conn, driverUserId);
      if (!driver || !driver.is_active || driver.user_is_active === 0) {
        throw new AppError('Driver not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.DRIVER_NOT_FOUND,
        });
      }
      hasActiveJob = await this.driverRepository.hasActiveJob(conn, driver.id);
      if (hasActiveJob && !allowActiveJob) {
        throw new AppError('Cannot go offline while an active trip is assigned', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.DRIVER_NOT_AVAILABLE,
        });
      }
      await this.driverRepository.updateOnlineState(conn, driver.id, {
        isOnline: false,
        status: DRIVER_STATUS.OFFLINE,
      });
      await conn.commit();
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }

    logger.info('Driver went offline', { driverId: driver.id, hasActiveJob });
    return this.getStatus(driverUserId).then((status) => ({ ...status, hasActiveJob }));
  }

  async goOfflineBestEffort(driverUserId) {
    try {
      await this.goOffline(driverUserId);
    } catch (err) {
      logger.warn('Best-effort driver offline update failed', {
        driverUserId,
        errorCode: err.errorCode,
      });
    }
  }
}

module.exports = DriverStatusService;
module.exports.CALL_ELIGIBILITY = CALL_ELIGIBILITY;

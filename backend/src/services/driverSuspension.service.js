const AppError = require("../utils/AppError");
const HTTP_STATUS = require("../constants/httpStatus");
const ERROR_CODES = require("../constants/errorCodes");
const {
  parseServiceDateTimeToMs,
  formatServiceDateTimeIso,
} = require("../utils/serviceDateTime.util");
const {
  ADMIN_SUSPENDED_DRIVER_RELEASE,
} = require("../constants/bookingAssignmentRelease.constants");
const { getRealtimeIo, driverUserRoom } = require("../socket/realtime");

const RUNNING = new Set(["ON_ROUTE", "DRIVER_ARRIVED", "PICKED_UP"]);
const DAY_MS = 24 * 60 * 60 * 1000;

class DriverSuspensionService {
  constructor({
    pool,
    driverRepository,
    userRepository,
    bookingRepository,
    bookingAssignmentReopenService,
    driverCallService,
  }) {
    this.pool = pool;
    this.driverRepository = driverRepository;
    this.userRepository = userRepository;
    this.bookingRepository = bookingRepository;
    this.bookingAssignmentReopenService = bookingAssignmentReopenService;
    this.driverCallService = driverCallService;
  }

  classify(rows, nowMs = Date.now()) {
    const releasable = [];
    const blocking = [];
    for (const row of rows) {
      const pickupMs = parseServiceDateTimeToMs(row.scheduled_pickup_at);
      const item = {
        bookingNumber: row.booking_number,
        pickupAt: formatServiceDateTimeIso(row.scheduled_pickup_at),
        within24Hours:
          pickupMs != null && pickupMs >= nowMs && pickupMs - nowMs <= DAY_MS,
        reason: null,
      };
      if (
        row.status === "DRIVER_ASSIGNED" &&
        pickupMs != null &&
        pickupMs > nowMs
      ) {
        releasable.push(item);
      } else {
        item.reason = RUNNING.has(row.status)
          ? "TRIP_IN_PROGRESS"
          : "PICKUP_TIME_PASSED_OR_MISSING";
        blocking.push(item);
      }
    }
    return { releasable, blocking };
  }

  async getDriverForUpdate(conn, driverId) {
    const driver = await this.driverRepository.findByIdForUpdate(
      conn,
      Number(driverId),
    );
    if (!driver)
      throw new AppError("Driver not found", {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.DRIVER_NOT_FOUND,
      });
    return driver;
  }

  async preview(driverId, now = new Date()) {
    const driver = await this.driverRepository.findById(Number(driverId));
    if (!driver)
      throw new AppError("Driver not found", {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.DRIVER_NOT_FOUND,
      });
    const rows = await this.driverRepository.listAssignmentsForSuspension(
      this.pool,
      Number(driverId),
    );
    const result = this.classify(rows, now.getTime());
    return {
      driverId: Number(driverId),
      currentStatus: driver.status,
      canSuspend: result.blocking.length === 0,
      ...result,
    };
  }

  async suspend(driverId, reason, actor, now = new Date()) {
    const conn = await this.pool.getConnection();
    const effects = [];
    let driver;
    let classification;
    try {
      await conn.beginTransaction();
      driver = await this.getDriverForUpdate(conn, driverId);
      const rows = await this.driverRepository.listAssignmentsForSuspension(
        conn,
        driver.id,
        { forUpdate: true },
      );
      classification = this.classify(rows, now.getTime());
      if (classification.blocking.length) {
        throw new AppError("Driver has active or overdue assignments", {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.DRIVER_HAS_ACTIVE_TRIPS,
          details: {
            bookingNumbers: classification.blocking.map((v) => v.bookingNumber),
          },
        });
      }
      for (const item of classification.releasable) {
        const booking =
          await this.bookingRepository.findByBookingNumberForUpdate(
            conn,
            item.bookingNumber,
          );
        const active =
          await this.bookingRepository.findActiveAssignmentForUpdate(
            conn,
            booking.id,
          );
        effects.push(
          await this.bookingAssignmentReopenService.reopenAssignedBookingInTransaction(
            conn,
            {
              booking,
              bookingNumber: item.bookingNumber,
              activeAssignment: active,
              actorUserId: actor.id,
              actorRole: actor.role,
              assignmentReleaseMarker: ADMIN_SUSPENDED_DRIVER_RELEASE,
              assignmentSocketReasonCode: ADMIN_SUSPENDED_DRIVER_RELEASE,
              statusLogMemo: reason,
              activityType: "DRIVER_SUSPENSION_REOPENED",
              activityDescription:
                "Driver suspended; future assignment reopened",
              activityPayload: {
                driverId: driver.id,
                reason,
                reasonCode: ADMIN_SUSPENDED_DRIVER_RELEASE,
              },
              reassignmentPriority: item.within24Hours ? "URGENT" : "NORMAL",
              releasedDriverUserId: driver.user_id,
              mapOpenCall: (row) => this.driverCallService.mapOpenCall(row),
            },
          ),
        );
      }
      await this.driverRepository.updateSuspensionState(conn, driver.id, {
        suspended: true,
        actorUserId: actor.id,
      });
      await this.userRepository.incrementAuthTokenVersion(conn, driver.user_id);
      await this.driverRepository.insertAuditLog(conn, {
        userId: actor.id,
        action: "DRIVER_SUSPENDED",
        driverId: driver.id,
        payload: {
          reason,
          previousStatus: driver.status,
          nextStatus: "SUSPENDED",
          releasedBookings: classification.releasable.map(
            (v) => v.bookingNumber,
          ),
        },
      });
      await conn.commit();
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }

    for (const effect of effects) {
      try {
        await this.bookingAssignmentReopenService.emitReopenEvents({
          ...effect,
          releasedDriverUserId: driver.user_id,
        });
      } catch (err) {
        console.error(
          "[driver-suspension] post-commit reopen notification failed",
          err?.message ?? err,
        );
      }
    }
    getRealtimeIo()?.in(driverUserRoom(driver.user_id)).disconnectSockets(true);
    return {
      driverId: driver.id,
      status: "SUSPENDED",
      releasedBookings: classification.releasable,
    };
  }

  async unsuspend(driverId, reason, actor) {
    const conn = await this.pool.getConnection();
    let driver;
    try {
      await conn.beginTransaction();
      driver = await this.getDriverForUpdate(conn, driverId);
      if (driver.status !== "SUSPENDED")
        throw new AppError("Driver is not suspended", {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.DRIVER_NOT_ELIGIBLE,
        });
      await this.driverRepository.updateSuspensionState(conn, driver.id, {
        suspended: false,
        actorUserId: actor.id,
      });
      await this.driverRepository.insertAuditLog(conn, {
        userId: actor.id,
        action: "DRIVER_UNSUSPENDED",
        driverId: driver.id,
        payload: { reason, previousStatus: "SUSPENDED", nextStatus: "OFFLINE" },
      });
      await conn.commit();
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
    return { driverId: driver.id, status: "OFFLINE", online: false };
  }

  async history(driverId) {
    return (
      await this.driverRepository.listSuspensionHistory(Number(driverId))
    ).map((row) => ({
      action: row.action,
      reason: this.parseAuditPayload(row.payload).reason ?? null,
      actorUserId: row.user_id,
      createdAt: formatServiceDateTimeIso(row.created_at),
    }));
  }

  parseAuditPayload(payload) {
    if (payload == null) return {};
    if (Buffer.isBuffer(payload)) payload = payload.toString("utf8");
    if (typeof payload === "object") return payload;
    try {
      return JSON.parse(payload);
    } catch (_) {
      return {};
    }
  }
}

module.exports = DriverSuspensionService;

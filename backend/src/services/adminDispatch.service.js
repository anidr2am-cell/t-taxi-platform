const { randomUUID } = require('node:crypto');
const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const BOOKING_STATUS = require('../constants/reservationStatus');
const ROLES = require('../constants/roles');
const { appEvents, EVENTS } = require('../events');

const TERMINAL_ASSIGN_STATUSES = new Set([
  BOOKING_STATUS.CANCELLED,
  BOOKING_STATUS.COMPLETED,
  BOOKING_STATUS.NO_SHOW,
]);

const TERMINAL_REASSIGN_STATUSES = new Set([
  BOOKING_STATUS.PICKED_UP,
  BOOKING_STATUS.COMPLETED,
  BOOKING_STATUS.CANCELLED,
  BOOKING_STATUS.NO_SHOW,
]);

class AdminDispatchService {
  constructor(
    pool,
    bookingRepository,
    driverRepository,
    bookingStatusService,
  ) {
    this.pool = pool;
    this.bookingRepository = bookingRepository;
    this.driverRepository = driverRepository;
    this.bookingStatusService = bookingStatusService;
  }

  actorFromUser(user) {
    return { id: user.id, role: user.role };
  }

  parsePagination(query) {
    const page = Number(query.page) || 1;
    const limit = Number(query.limit ?? query.page_size) || 20;
    const safeLimit = Math.min(Math.max(limit, 1), 100);
    const offset = (Math.max(page, 1) - 1) * safeLimit;
    return { page: Math.max(page, 1), limit: safeLimit, offset };
  }

  parseFilters(query) {
    const filters = {
      search: query.search?.trim() || null,
      status: query.status || null,
      driverId: query.driverId ? Number(query.driverId) : null,
      assignmentState: query.assignmentState || null,
      serviceDateFrom: null,
      serviceDateTo: null,
    };

    if (query.serviceDateFrom) {
      filters.serviceDateFrom = `${query.serviceDateFrom} 00:00:00`;
    }
    if (query.serviceDateTo) {
      const end = new Date(`${query.serviceDateTo}T00:00:00`);
      end.setDate(end.getDate() + 1);
      filters.serviceDateTo = end.toISOString().slice(0, 19).replace('T', ' ');
    }

    return filters;
  }

  formatLuggageSummary(row) {
    const parts = [];
    if (row.carriers_20_inch) parts.push(`20":${row.carriers_20_inch}`);
    if (row.carriers_24_inch_plus) parts.push(`24+":${row.carriers_24_inch_plus}`);
    if (row.golf_bags) parts.push(`golf:${row.golf_bags}`);
    if (row.special_items) parts.push(row.special_items);
    return parts.length ? parts.join(', ') : null;
  }

  mapActiveAssignment(row) {
    if (!row.assignment_id) return null;
    return {
      assignmentId: row.assignment_id,
      driverId: row.assignment_driver_id,
      driverDisplayName: row.driver_name,
      driverPhone: row.driver_phone,
      status: row.assignment_status,
      isActive: true,
    };
  }

  mapQueueItem(row) {
    const passengerCount = (row.adults ?? 0) + (row.children ?? 0) + (row.infants ?? 0);
    return {
      bookingNumber: row.booking_number,
      status: row.status,
      serviceType: {
        code: row.service_type_code,
        name: row.service_type_name,
      },
      scheduledPickupAt: row.scheduled_pickup_at,
      origin: row.origin_address,
      destination: row.destination_address,
      customerDisplayName: row.customer_name,
      customerPhone: row.customer_phone,
      passengerCount,
      luggageSummary: this.formatLuggageSummary(row),
      vehicleType: {
        code: row.vehicle_type_code,
        name: row.vehicle_type_name,
      },
      flightNumber: row.flight_number,
      flightStatus: row.delay_status,
      paymentMethod: row.payment_method,
      totalAmount: Number(row.total_amount),
      currency: row.currency,
      activeAssignment: this.mapActiveAssignment(row),
      createdAt: row.created_at,
    };
  }

  mapDriverEligibility(driver) {
    if (!driver.is_active || driver.status === 'SUSPENDED') {
      return 'NOT_ELIGIBLE';
    }
    if (driver.status === 'OFFLINE' || !driver.is_online) {
      return 'INACTIVE';
    }
    return 'ACTIVE';
  }

  isDriverAssignable(driver) {
    return driver.is_active === 1 && driver.status !== 'SUSPENDED';
  }

  mapDriverListItem(row) {
    const eligibilityState = this.mapDriverEligibility(row);
    return {
      driverId: row.id,
      displayName: row.name,
      phone: row.phone,
      activeState: row.is_active ? 'ACTIVE' : 'INACTIVE',
      onlineState: row.is_online ? 'ONLINE' : 'OFFLINE',
      driverStatus: row.status,
      eligibilityState,
      assignmentEligible: eligibilityState !== 'NOT_ELIGIBLE',
      primaryVehicle: row.primary_vehicle_id
        ? {
            vehicleId: row.primary_vehicle_id,
            vehicleTypeCode: row.primary_vehicle_type_code,
            vehicleTypeName: row.primary_vehicle_type_name,
            plateNumber: row.primary_vehicle_plate,
            modelName: row.primary_vehicle_model,
          }
        : null,
      activeAssignmentCount: Number(row.active_assignment_count ?? 0),
    };
  }

  computeAllowedActions(booking, activeAssignment) {
    const actions = [];
    const status = booking.status;
    const terminalAssign = TERMINAL_ASSIGN_STATUSES.has(status);
    const terminalReassign = TERMINAL_REASSIGN_STATUSES.has(status);

    if (!activeAssignment && !terminalAssign) {
      actions.push('ASSIGN_DRIVER');
    }
    if (activeAssignment && !terminalReassign) {
      actions.push('REASSIGN_DRIVER');
    }
    return actions;
  }

  parseMetadata(raw) {
    if (!raw) return null;
    if (typeof raw === 'object') return raw;
    try {
      return JSON.parse(raw);
    } catch {
      return null;
    }
  }

  async listBookings(query) {
    const filters = this.parseFilters(query);
    const pagination = this.parsePagination(query);
    const total = await this.bookingRepository.countAdminBookings(filters);
    const rows = await this.bookingRepository.findAdminBookings(filters, pagination);

    return {
      page: pagination.page,
      pageSize: pagination.limit,
      total,
      items: rows.map((row) => this.mapQueueItem(row)),
    };
  }

  async getBookingDetail(bookingNumber) {
    const row = await this.bookingRepository.findAdminBookingDetail(bookingNumber);
    if (!row) {
      throw new AppError('Booking not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
      });
    }

    const chargeItems = await this.bookingRepository.findChargeItemsByBookingId(row.id);
    const statusHistory = await this.bookingRepository.findStatusLogsByBookingId(row.id);
    const assignments = await this.bookingRepository.findAssignmentsByBookingId(row.id);
    const activeAssignment = assignments.find((a) => a.is_active === 1) ?? null;
    const metadata = this.parseMetadata(row.metadata);

    return {
      bookingNumber: row.booking_number,
      status: row.status,
      serviceType: {
        code: row.service_type_code,
        name: row.service_type_name,
      },
      scheduledPickupAt: row.scheduled_pickup_at,
      route: {
        origin: {
          address: row.origin_address,
          placeId: row.origin_place_id,
          lat: row.origin_lat,
          lng: row.origin_lng,
        },
        destination: {
          address: row.destination_address,
          placeId: row.destination_place_id,
          lat: row.destination_lat,
          lng: row.destination_lng,
        },
      },
      customer: {
        name: row.customer_name,
        email: row.customer_email,
        phone: row.customer_phone,
        countryCode: row.customer_country_code,
        messengerType: metadata?.messengerType ?? null,
        messengerId: metadata?.messengerId ?? null,
      },
      specialRequests: row.special_requests,
      passengers: {
        adults: row.adults ?? 0,
        children: row.children ?? 0,
        infants: row.infants ?? 0,
      },
      luggage: {
        carriers20Inch: row.carriers_20_inch ?? 0,
        carriers24InchPlus: row.carriers_24_inch_plus ?? 0,
        golfBags: row.golf_bags ?? 0,
        specialItems: row.special_items,
      },
      vehicle: {
        typeCode: row.vehicle_type_code,
        typeName: row.vehicle_type_name,
        count: row.vehicle_count,
      },
      flight: {
        flightNumber: row.flight_number,
        airportIata: row.airport_iata ?? row.airport_code_custom,
        scheduledArrivalAt: row.flight_scheduled_arrival_at,
        estimatedArrivalAt: row.flight_estimated_arrival_at,
        delayStatus: row.delay_status,
        delayMinutes: row.delay_minutes,
      },
      pricing: {
        totalAmount: Number(row.total_amount),
        currency: row.currency,
        paymentMethod: row.payment_method,
        paymentStatus: row.payment_status,
        chargeItems: chargeItems.map((item) => ({
          chargeType: item.charge_type,
          description: item.description,
          quantity: Number(item.quantity),
          unitPrice: Number(item.unit_price),
          amount: Number(item.amount),
        })),
      },
      commissionStatus: row.commission_status,
      activeAssignment: activeAssignment
        ? {
            assignmentId: activeAssignment.id,
            driverId: activeAssignment.driver_id,
            driverDisplayName: activeAssignment.driver_name,
            driverPhone: activeAssignment.driver_phone,
            status: activeAssignment.status,
            isActive: true,
            assignedAt: activeAssignment.assigned_at,
            assignmentReason: activeAssignment.assignment_reason,
          }
        : null,
      assignmentHistory: assignments.map((item) => ({
        assignmentId: item.id,
        driverId: item.driver_id,
        driverDisplayName: item.driver_name,
        driverPhone: item.driver_phone,
        status: item.status,
        isActive: item.is_active === 1,
        assignedAt: item.assigned_at,
        unassignedAt: item.unassigned_at,
        assignmentReason: item.assignment_reason,
      })),
      statusHistory: statusHistory.map((item) => ({
        fromStatus: item.from_status,
        toStatus: item.to_status,
        changedByRole: item.changed_by_role,
        reason: item.reason,
        memo: item.memo,
        createdAt: item.created_at,
      })),
      allowedActions: this.computeAllowedActions(row, activeAssignment),
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }

  async listDrivers() {
    const rows = await this.driverRepository.listForAdminAssignment();
    return rows.map((row) => this.mapDriverListItem(row));
  }

  async ensureDriverEligible(conn, driverId) {
    const driver = await this.driverRepository.findByIdForUpdate(conn, driverId);
    if (!driver) {
      throw new AppError('Driver not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.DRIVER_NOT_FOUND,
      });
    }
    if (!this.isDriverAssignable(driver)) {
      throw new AppError('Driver is not eligible for assignment', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.DRIVER_NOT_ELIGIBLE,
      });
    }
    return driver;
  }

  async transitionToDriverAssigned(conn, bookingNumber, actor, initialStatus) {
    const transitions = [];
    if (initialStatus === BOOKING_STATUS.PENDING) {
      transitions.push(BOOKING_STATUS.CONFIRMED);
    }
    if (
      initialStatus === BOOKING_STATUS.PENDING
      || initialStatus === BOOKING_STATUS.CONFIRMED
    ) {
      transitions.push(BOOKING_STATUS.DRIVER_ASSIGNED);
    }

    const events = [];
    for (const status of transitions) {
      const result = await this.bookingStatusService.transitionInTransaction(
        conn,
        bookingNumber,
        { status },
        actor,
        { skipAccessCheck: true },
      );
      if (result.domainEvent) {
        events.push({ event: result.domainEvent, payload: result.eventPayload });
      }
    }
    return events;
  }

  async assignDriver(bookingNumber, input, user) {
    const actor = this.actorFromUser(user);
    const conn = await this.pool.getConnection();
    const pendingEvents = [];

    try {
      await conn.beginTransaction();

      const booking = await this.bookingRepository.findByBookingNumberForUpdate(conn, bookingNumber);
      if (!booking) {
        throw new AppError('Booking not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
        });
      }

      if (TERMINAL_ASSIGN_STATUSES.has(booking.status)) {
        throw new AppError('Booking cannot be assigned in the current status', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.INVALID_STATUS_TRANSITION,
        });
      }

      const active = await this.bookingRepository.findActiveAssignmentForUpdate(conn, booking.id);
      if (active) {
        throw new AppError('Booking already has an active driver assignment', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.ALREADY_ASSIGNED,
        });
      }

      const driver = await this.ensureDriverEligible(conn, input.driverId);
      let driverVehicleId = input.driverVehicleId ?? null;
      if (!driverVehicleId) {
        const primaryVehicle = await this.driverRepository.findPrimaryVehicle(conn, driver.id);
        driverVehicleId = primaryVehicle?.id ?? null;
      }

      const assignmentId = await this.bookingRepository.insertDriverAssignment(conn, {
        bookingId: booking.id,
        driverId: driver.id,
        driverVehicleId,
        assignedByUserId: actor.id,
        assignmentReason: input.assignmentReason ?? input.reason ?? null,
      });

      const statusEvents = await this.transitionToDriverAssigned(
        conn,
        bookingNumber,
        actor,
        booking.status,
      );
      pendingEvents.push(...statusEvents);

      await this.bookingRepository.insertActivityLog(conn, booking.id, {
        activityType: 'DRIVER_ASSIGNED',
        actorUserId: actor.id,
        actorRole: actor.role,
        description: `Driver ${driver.name} assigned by admin`,
        payload: {
          bookingNumber,
          driverId: driver.id,
          assignmentId,
        },
      });

      await conn.commit();

      for (const item of pendingEvents) {
        appEvents.emit(item.event, item.payload);
      }

      return {
        assignmentId,
        isActive: true,
        driver: {
          driverId: driver.id,
          displayName: driver.name,
          phone: driver.phone,
        },
        bookingStatus: BOOKING_STATUS.DRIVER_ASSIGNED,
      };
    } catch (err) {
      await conn.rollback();
      if (err.code === 'ER_DUP_ENTRY') {
        throw new AppError('Assignment conflict', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.ASSIGNMENT_CONFLICT,
        });
      }
      throw err;
    } finally {
      conn.release();
    }
  }

  async reassignDriver(bookingNumber, input, user) {
    const actor = this.actorFromUser(user);
    const conn = await this.pool.getConnection();
    let reassignEvent = null;
    let response;

    try {
      await conn.beginTransaction();

      const booking = await this.bookingRepository.findByBookingNumberForUpdate(conn, bookingNumber);
      if (!booking) {
        throw new AppError('Booking not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
        });
      }

      if (TERMINAL_REASSIGN_STATUSES.has(booking.status)) {
        throw new AppError('Booking cannot be reassigned in the current status', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.INVALID_STATUS_TRANSITION,
        });
      }

      const active = await this.bookingRepository.findActiveAssignmentForUpdate(conn, booking.id);
      if (!active) {
        throw new AppError('Booking has no active driver assignment', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.NO_ACTIVE_ASSIGNMENT,
        });
      }

      if (Number(active.driver_id) === Number(input.driverId)) {
        throw new AppError('New driver must differ from the current driver', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.VALIDATION_ERROR,
        });
      }

      const driver = await this.ensureDriverEligible(conn, input.driverId);
      let driverVehicleId = input.driverVehicleId ?? null;
      if (!driverVehicleId) {
        const primaryVehicle = await this.driverRepository.findPrimaryVehicle(conn, driver.id);
        driverVehicleId = primaryVehicle?.id ?? null;
      }

      const deactivated = await this.bookingRepository.deactivateAssignment(
        conn,
        active.id,
        input.reason ?? null,
      );
      if (!deactivated) {
        throw new AppError('Assignment conflict', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.ASSIGNMENT_CONFLICT,
        });
      }

      const assignmentId = await this.bookingRepository.insertDriverAssignment(conn, {
        bookingId: booking.id,
        driverId: driver.id,
        driverVehicleId,
        assignedByUserId: actor.id,
        assignmentReason: input.reason ?? input.assignmentReason ?? null,
      });

      await this.bookingRepository.insertActivityLog(conn, booking.id, {
        activityType: 'DRIVER_REASSIGNED',
        actorUserId: actor.id,
        actorRole: actor.role,
        description: `Driver reassigned to ${driver.name}`,
        payload: {
          bookingNumber,
          previousDriverId: active.driver_id,
          newDriverId: driver.id,
          reason: input.reason ?? null,
          assignmentId,
        },
      });

      await conn.commit();

      reassignEvent = {
        eventId: randomUUID(),
        eventName: EVENTS.DRIVER_REASSIGNED,
        bookingId: booking.id,
        bookingNumber,
        previousDriverId: active.driver_id,
        newDriverId: driver.id,
        assignmentId,
        actorUserId: actor.id,
        actorRole: actor.role,
        reason: input.reason ?? null,
        occurredAt: new Date().toISOString(),
      };

      response = {
        assignmentId,
        isActive: true,
        driver: {
          driverId: driver.id,
          displayName: driver.name,
          phone: driver.phone,
        },
        bookingStatus: booking.status,
      };
    } catch (err) {
      await conn.rollback();
      if (err.code === 'ER_DUP_ENTRY') {
        throw new AppError('Assignment conflict', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.ASSIGNMENT_CONFLICT,
        });
      }
      throw err;
    } finally {
      conn.release();
    }

    if (reassignEvent) {
      appEvents.emit(EVENTS.DRIVER_REASSIGNED, reassignEvent);
    }

    return response;
  }
}

module.exports = AdminDispatchService;

const { randomUUID } = require("node:crypto");
const AppError = require("../utils/AppError");
const HTTP_STATUS = require("../constants/httpStatus");
const ERROR_CODES = require("../constants/errorCodes");
const BOOKING_STATUS = require("../constants/reservationStatus");
const ROLES = require("../constants/roles");
const { EVENTS } = require("../events");
const { parseStoredTags } = require("../constants/reviewTags");
const AdminOperationsService = require("./adminOperations.service");
const { ADMIN_BOOKING_VIEWS } = require("../constants/adminOperations.constants");

const TERMINAL_ASSIGN_STATUSES = new Set([
  BOOKING_STATUS.CANCELLED,
  BOOKING_STATUS.COMPLETED,
  BOOKING_STATUS.NO_SHOW,
]);

const TERMINAL_REASSIGN_STATUSES = new Set([
  BOOKING_STATUS.PICKED_UP,
  BOOKING_STATUS.SETTLEMENT_PENDING,
  BOOKING_STATUS.COMPLETED,
  BOOKING_STATUS.CANCELLED,
  BOOKING_STATUS.NO_SHOW,
]);

const CANDIDATE_ASSIGN_STATUSES = new Set([
  BOOKING_STATUS.PENDING,
  BOOKING_STATUS.OPEN,
  BOOKING_STATUS.CONFIRMED,
]);

class AdminDispatchService {
  constructor(
    pool,
    bookingRepository,
    driverRepository,
    bookingStatusService,
    commissionSettlementService,
    outboxRepository,
    outboxProcessor,
    driverCandidateScoringService,
    adminQrReissueService = null,
    chatService = null,
    reviewRepository = null,
  ) {
    this.pool = pool;
    this.bookingRepository = bookingRepository;
    this.driverRepository = driverRepository;
    this.bookingStatusService = bookingStatusService;
    this.commissionSettlementService = commissionSettlementService;
    this.outboxRepository = outboxRepository;
    this.outboxProcessor = outboxProcessor;
    this.driverCandidateScoringService = driverCandidateScoringService;
    this.adminQrReissueService = adminQrReissueService;
    this.chatService = chatService;
    this.reviewRepository = reviewRepository;
    this.adminOperationsService = new AdminOperationsService();
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
      filters.serviceDateTo = end.toISOString().slice(0, 19).replace("T", " ");
    }

    return filters;
  }

  formatLuggageSummary(row) {
    const parts = [];
    if (row.carriers_20_inch) parts.push(`20":${row.carriers_20_inch}`);
    if (row.carriers_24_inch_plus)
      parts.push(`24+":${row.carriers_24_inch_plus}`);
    if (row.golf_bags) parts.push(`golf:${row.golf_bags}`);
    if (row.special_items) parts.push(row.special_items);
    return parts.length ? parts.join(", ") : null;
  }

  mapActiveAssignment(row) {
    if (!row.assignment_id) return null;
    const vehicle =
      row.assigned_vehicle_type_code ||
      row.assigned_vehicle_plate ||
      row.assigned_vehicle_model
        ? {
            typeCode: row.assigned_vehicle_type_code ?? null,
            typeName: row.assigned_vehicle_type_name ?? null,
            plateNumber: row.assigned_vehicle_plate ?? null,
            modelName: row.assigned_vehicle_model ?? null,
          }
        : null;
    return {
      assignmentId: row.assignment_id,
      driverId: row.assignment_driver_id,
      driverDisplayName: row.driver_name,
      driverStatus: row.driver_status ?? null,
      vehicle,
      status: row.assignment_status,
      isActive: true,
    };
  }

  mapQueueItem(row) {
    const passengerCount =
      (row.adults ?? 0) + (row.children ?? 0) + (row.infants ?? 0);
    const operations = this.adminOperationsService.evaluateOperations(row);
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
      bookingGroup: row.is_new_booking ? "NEW" : "EXISTING",
      archive: {
        isArchived: Boolean(row.is_archived),
        archivedAt: row.archived_at ?? null,
        archivedBy: row.archived_by ?? null,
        reason: row.archive_reason ?? null,
      },
      createdAt: row.created_at,
      operations,
      primaryCta: operations.primaryCta,
    };
  }

  mapDriverEligibility(driver) {
    if (!driver.is_active || driver.status === "SUSPENDED") {
      return "NOT_ELIGIBLE";
    }
    if (driver.status === "OFFLINE" || !driver.is_online) {
      return "INACTIVE";
    }
    return "ACTIVE";
  }

  isDriverAssignable(driver) {
    return driver.is_active === 1 && driver.status !== "SUSPENDED";
  }

  mapDriverListItem(
    row,
    settlementBlocked = false,
    settlementBlockReason = null,
  ) {
    const eligibilityState = settlementBlocked
      ? "NOT_ELIGIBLE"
      : this.mapDriverEligibility(row);
    return {
      driverId: row.id,
      displayName: row.name,
      phone: row.phone,
      activeState: row.is_active ? "ACTIVE" : "INACTIVE",
      onlineState: row.is_online ? "ONLINE" : "OFFLINE",
      driverStatus: row.status,
      eligibilityState,
      assignmentEligible: eligibilityState !== "NOT_ELIGIBLE",
      settlementBlockReason: settlementBlockReason ?? null,
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
      averageRating:
        row.average_rating != null ? Number(row.average_rating) : null,
      reviewCount: Number(row.review_count ?? 0),
    };
  }

  computeAllowedActions(booking, activeAssignment) {
    const actions = [];
    const status = booking.status;
    const terminalAssign = TERMINAL_ASSIGN_STATUSES.has(status);
    const terminalReassign = TERMINAL_REASSIGN_STATUSES.has(status);

    if (!activeAssignment && !terminalAssign) {
      actions.push("ASSIGN_DRIVER");
    }
    if (activeAssignment && !terminalReassign) {
      actions.push("REASSIGN_DRIVER");
    }
    return actions;
  }

  parseMetadata(raw) {
    if (!raw) return null;
    if (typeof raw === "object") return raw;
    try {
      return JSON.parse(raw);
    } catch {
      return null;
    }
  }

  mapAssignmentVehicle(row) {
    if (!row.vehicle_type_code && !row.vehicle_plate && !row.vehicle_model) {
      return null;
    }
    return {
      typeCode: row.vehicle_type_code ?? null,
      typeName: row.vehicle_type_name ?? null,
      plateNumber: row.vehicle_plate ?? null,
      modelName: row.vehicle_model ?? null,
    };
  }

  async listBookings(query, actorUser = null) {
    const adminUserId = this.adminOperationsService.resolveAdminUserId(actorUser);
    const filters = this.adminOperationsService.buildFilters(
      query,
      adminUserId,
    );
    if (filters.invalidView) {
      throw new AppError("Invalid booking view", {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }

    const pagination = this.parsePagination(query);
    const total = await this.bookingRepository.countAdminBookings(filters);
    const rows = await this.bookingRepository.findAdminBookings(
      filters,
      pagination,
    );

    let items = rows.map((row) => this.mapQueueItem(row));
    if (
      filters.view === ADMIN_BOOKING_VIEWS.NEEDS_ACTION ||
      filters.view === ADMIN_BOOKING_VIEWS.ISSUES
    ) {
      items = this.adminOperationsService.sortQueueItems(items);
    }

    return {
      page: pagination.page,
      pageSize: pagination.limit,
      total,
      view: filters.view,
      items,
    };
  }

  async getBookingsSummary(actorUser = null) {
    const adminUserId = this.adminOperationsService.resolveAdminUserId(actorUser);
    const keys = this.adminOperationsService.summaryViewKeys();
    const entries = await Promise.all(
      keys.map(async (key) => {
        const filters = this.adminOperationsService.buildSummaryFilter(
          key,
          adminUserId,
        );
        const count = await this.bookingRepository.countAdminBookings(filters);
        return [key, count];
      }),
    );
    const summary = Object.fromEntries(entries);
    return {
      needsAction: summary.needs_action ?? 0,
      unassigned: summary.unassigned ?? 0,
      today: summary.today ?? 0,
      inProgress: summary.in_progress ?? 0,
      settlementPending: summary.settlement ?? 0,
      issues: summary.issues ?? 0,
    };
  }

  async getBookingDetail(bookingNumber, actorUser = null) {
    const adminUserId = this.adminOperationsService.resolveAdminUserId(actorUser);
    const row =
      await this.bookingRepository.findAdminBookingDetail(bookingNumber);
    if (!row) {
      throw new AppError("Booking not found", {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
      });
    }

    const chargeItems = await this.bookingRepository.findChargeItemsByBookingId(
      row.id,
    );
    const statusHistory =
      await this.bookingRepository.findStatusLogsByBookingId(row.id);
    const assignments = await this.bookingRepository.findAssignmentsByBookingId(
      row.id,
    );
    const activeAssignment = assignments.find((a) => a.is_active === 1) ?? null;
    const metadata = this.parseMetadata(row.metadata);
    const reviewRow = this.reviewRepository
      ? await this.reviewRepository.findByBookingId(row.id)
      : null;
    const customerReview = reviewRow
      ? {
          reviewId: reviewRow.id,
          rating: reviewRow.rating,
          tags: parseStoredTags(reviewRow.tags_json),
          comment: reviewRow.comment,
          lowRating: Number(reviewRow.rating) <= 2,
          createdAt: reviewRow.created_at,
        }
      : null;

    const adminUnreadCount = adminUserId
      ? await this.bookingRepository.countAdminUnreadForBooking(
          adminUserId,
          row.id,
        )
      : 0;

    const operations = this.adminOperationsService.evaluateOperations({
      status: row.status,
      scheduled_pickup_at: row.scheduled_pickup_at,
      driver_id: row.driver_id,
      assignment_id: activeAssignment?.id ?? null,
      commission_status: row.commission_status,
      commission_receipt_file_id: row.commission_receipt_file_id,
      metadata: row.metadata,
      updated_at: row.updated_at,
      review_rating: reviewRow?.rating ?? null,
      admin_unread_count: adminUnreadCount,
    });

    return {
      bookingNumber: row.booking_number,
      status: row.status,
      archive: {
        isArchived: Boolean(row.is_archived),
        archivedAt: row.archived_at ?? null,
        archivedBy: row.archived_by ?? null,
        reason: row.archive_reason ?? null,
      },
      operations,
      primaryCta: operations.primaryCta,
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
            driverStatus: activeAssignment.driver_status ?? null,
            vehicle: this.mapAssignmentVehicle(activeAssignment),
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
        driverStatus: item.driver_status ?? null,
        vehicle: this.mapAssignmentVehicle(item),
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
      allowedActions: row.is_archived
        ? []
        : this.computeAllowedActions(row, activeAssignment),
      customerReview,
      devQrTools: this.adminQrReissueService?.buildDevTools(row) ?? {
        qrReissueEnabled: false,
        disabledReason: "QR reissue service unavailable",
        boarding: {
          reissueAvailable: false,
          consumed: false,
          previouslyIssued: false,
          unavailableReason: null,
        },
        dropoff: {
          reissueAvailable: false,
          consumed: false,
          previouslyIssued: false,
          unavailableReason: null,
        },
      },
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }

  normalizeBookingNumbers(values) {
    return [...new Set(
      (values ?? [])
        .map((value) => String(value ?? "").trim().toUpperCase())
        .filter((value) => /^TX\d{12}$/.test(value)),
    )];
  }

  archiveWarningsFor(row) {
    const warnings = [];
    const operatingStatuses = new Set([
      BOOKING_STATUS.DRIVER_ASSIGNED,
      BOOKING_STATUS.ON_ROUTE,
      BOOKING_STATUS.DRIVER_ARRIVED,
      BOOKING_STATUS.PICKED_UP,
      BOOKING_STATUS.SETTLEMENT_PENDING,
      BOOKING_STATUS.COMPLETED,
    ]);
    if (operatingStatuses.has(row.status) || row.has_assignment) {
      warnings.push("HAS_OPERATION_RECORD");
    }
    if (row.status === BOOKING_STATUS.COMPLETED || row.commission_status === "PAID") {
      warnings.push("COMPLETED_OR_SETTLED");
    }
    if (row.has_trip_status_log) {
      warnings.push("HAS_TRIP_STATUS_LOG");
    }
    return warnings;
  }

  async archiveBookings(input, user) {
    const actor = this.actorFromUser(user);
    const bookingNumbers = this.normalizeBookingNumbers(input.bookingNumbers);
    if (!bookingNumbers.length) {
      throw new AppError("Booking numbers are required", {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }

    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      const rows = await this.bookingRepository.findArchiveCandidatesForUpdate(
        conn,
        bookingNumbers,
      );
      const foundNumbers = new Set(rows.map((row) => row.booking_number));
      const missing = bookingNumbers.filter((number) => !foundNumbers.has(number));
      if (missing.length) {
        throw new AppError("One or more bookings were not found", {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
        });
      }

      const ids = rows.map((row) => row.id);
      await this.bookingRepository.archiveBookings(conn, ids, {
        actorUserId: actor.id,
        reason: "TEST_DATA",
      });

      const results = rows.map((row) => ({
        bookingNumber: row.booking_number,
        wasArchived: Boolean(row.is_archived),
        warnings: this.archiveWarningsFor(row),
      }));

      for (const row of rows) {
        await this.bookingRepository.insertActivityLog(conn, row.id, {
          activityType: "BOOKING_ARCHIVED",
          actorUserId: actor.id,
          actorRole: actor.role,
          description: "Booking hidden as test data",
          payload: {
            bookingNumber: row.booking_number,
            reason: "TEST_DATA",
            warnings: this.archiveWarningsFor(row),
          },
        });
      }

      await conn.commit();
      return { archived: results.length, items: results };
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }

  async restoreBookings(input, user) {
    const actor = this.actorFromUser(user);
    const bookingNumbers = this.normalizeBookingNumbers(input.bookingNumbers);
    if (!bookingNumbers.length) {
      throw new AppError("Booking numbers are required", {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }

    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      const rows = await this.bookingRepository.findArchiveCandidatesForUpdate(
        conn,
        bookingNumbers,
      );
      const foundNumbers = new Set(rows.map((row) => row.booking_number));
      const missing = bookingNumbers.filter((number) => !foundNumbers.has(number));
      if (missing.length) {
        throw new AppError("One or more bookings were not found", {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
        });
      }

      const ids = rows.map((row) => row.id);
      await this.bookingRepository.restoreBookings(conn, ids, {
        actorUserId: actor.id,
      });

      for (const row of rows) {
        await this.bookingRepository.insertActivityLog(conn, row.id, {
          activityType: "BOOKING_RESTORED",
          actorUserId: actor.id,
          actorRole: actor.role,
          description: "Archived booking restored",
          payload: {
            bookingNumber: row.booking_number,
            previousReason: row.archive_reason ?? null,
          },
        });
      }

      await conn.commit();
      return {
        restored: rows.length,
        items: rows.map((row) => ({ bookingNumber: row.booking_number })),
      };
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }

  async listDrivers() {
    const rows = await this.driverRepository.listForAdminAssignment();
    const items = [];
    for (const row of rows) {
      const blocked =
        await this.commissionSettlementService.driverHasBlockingSettlement(
          row.id,
        );
      const blockReason = blocked
        ? "Outstanding overdue or unresolved commission settlement"
        : null;
      items.push(this.mapDriverListItem(row, blocked, blockReason));
    }
    return items;
  }

  async ensureDriverEligible(conn, driverId) {
    const driver = await this.driverRepository.findByIdForUpdate(
      conn,
      driverId,
    );
    if (!driver) {
      throw new AppError("Driver not found", {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.DRIVER_NOT_FOUND,
      });
    }
    if (!this.isDriverAssignable(driver)) {
      throw new AppError("Driver is not eligible for assignment", {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.DRIVER_NOT_ELIGIBLE,
      });
    }
    const hasActiveJob = await this.driverRepository.hasActiveJob(conn, driver.id);
    if (hasActiveJob) {
      throw new AppError(
        "This driver has an active or unsettled job and cannot receive a new booking.",
        {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.DRIVER_NOT_ELIGIBLE,
        },
      );
    }
    const blocked =
      await this.commissionSettlementService.driverHasBlockingSettlement(
        driver.id,
      );
    if (blocked) {
      throw new AppError(
        "This driver cannot receive a new job until the previous settlement is confirmed.",
        {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.DRIVER_NOT_ELIGIBLE,
        },
      );
    }
    return driver;
  }

  assertBookingSupportsCandidateRecommendation(booking, activeAssignment) {
    if (activeAssignment) {
      throw new AppError("Booking already has an active driver assignment", {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.ALREADY_ASSIGNED,
      });
    }
    if (!CANDIDATE_ASSIGN_STATUSES.has(booking.status)) {
      throw new AppError("Booking is not eligible for driver recommendation", {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.INVALID_STATUS_TRANSITION,
      });
    }
    if (TERMINAL_ASSIGN_STATUSES.has(booking.status)) {
      throw new AppError("Booking cannot be assigned in the current status", {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.INVALID_STATUS_TRANSITION,
      });
    }
  }

  async buildDriverCandidatePreview(booking) {
    const drivers = await this.driverRepository.listForCandidateEvaluation(
      booking.scheduled_pickup_at,
    );
    const candidates = [];
    const excluded = [];

    for (const driver of drivers) {
      const settlementBlocked =
        await this.commissionSettlementService.driverHasBlockingSettlement(
          driver.id,
        );
      const candidate = this.driverCandidateScoringService.buildCandidate(
        driver,
        booking,
        { settlementBlocked },
      );
      if (candidate.eligible) {
        candidates.push({
          driverId: candidate.driverId,
          displayName: candidate.displayName,
          vehicleTypeCode: candidate.vehicleTypeCode,
          online: candidate.online,
          activeJobCount: candidate.activeJobCount,
          distanceKm: candidate.distanceKm,
          locationFresh: candidate.locationFresh,
          score: candidate.score,
          reasons: candidate.reasons,
          eligible: true,
          lastAssignedAt: candidate.lastAssignedAt,
        });
      } else {
        excluded.push({
          driverId: candidate.driverId,
          displayName: candidate.displayName,
          reasons: candidate.exclusionReasons,
        });
      }
    }

    candidates.sort((a, b) =>
      this.driverCandidateScoringService.compareCandidates(a, b),
    );

    return {
      candidates,
      excluded,
      recommendedDriverId: candidates[0]?.driverId ?? null,
    };
  }

  async getDriverCandidates(bookingNumber) {
    const booking =
      await this.bookingRepository.findBookingForDriverCandidates(
        bookingNumber,
      );
    if (!booking) {
      throw new AppError("Booking not found", {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
      });
    }

    const assignments = await this.bookingRepository.findAssignmentsByBookingId(
      booking.id,
    );
    const activeAssignment =
      assignments.find((row) => row.is_active === 1) ?? null;
    this.assertBookingSupportsCandidateRecommendation(
      booking,
      activeAssignment,
    );

    const preview = await this.buildDriverCandidatePreview(booking);

    return {
      bookingId: booking.id,
      bookingNumber: booking.booking_number,
      vehicleTypeCode: booking.vehicle_type_code,
      assignmentVersion: activeAssignment?.id ?? 0,
      recommendedDriverId: preview.recommendedDriverId,
      candidates: preview.candidates,
      excluded: preview.excluded,
    };
  }

  async assertAutoAssignCandidate(
    bookingNumber,
    driverId,
    expectedAssignmentVersion,
  ) {
    const preview = await this.getDriverCandidates(bookingNumber);
    if (
      expectedAssignmentVersion !== undefined &&
      Number(expectedAssignmentVersion) !== Number(preview.assignmentVersion)
    ) {
      throw new AppError("Assignment conflict", {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.ASSIGNMENT_CONFLICT,
      });
    }

    const candidate = preview.candidates.find(
      (row) => Number(row.driverId) === Number(driverId),
    );
    if (!candidate) {
      throw new AppError("Driver is not eligible for auto assignment", {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.DRIVER_NOT_ELIGIBLE,
      });
    }
    return candidate;
  }

  async autoAssignDriver(bookingNumber, input, user) {
    let driverId = input.driverId;
    if (input.useTopCandidate) {
      const preview = await this.getDriverCandidates(bookingNumber);
      const top = preview.candidates[0];
      if (!top) {
        throw new AppError(
          "No eligible drivers available for auto assignment",
          {
            statusCode: HTTP_STATUS.CONFLICT,
            errorCode: ERROR_CODES.DRIVER_NOT_ELIGIBLE,
          },
        );
      }
      driverId = top.driverId;
    }

    if (!driverId) {
      throw new AppError("driverId or useTopCandidate is required", {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }

    await this.assertAutoAssignCandidate(
      bookingNumber,
      driverId,
      input.expectedAssignmentVersion,
    );

    return this.assignDriver(
      bookingNumber,
      {
        driverId,
        assignmentReason: input.assignmentReason ?? "AUTO_ASSIGN",
      },
      user,
    );
  }

  async transitionToDriverAssigned(conn, bookingNumber, actor, initialStatus) {
    const transitions = [];
    if (initialStatus === BOOKING_STATUS.PENDING) {
      transitions.push(BOOKING_STATUS.CONFIRMED);
    }
    if (
      initialStatus === BOOKING_STATUS.PENDING ||
      initialStatus === BOOKING_STATUS.OPEN ||
      initialStatus === BOOKING_STATUS.CONFIRMED
    ) {
      transitions.push(BOOKING_STATUS.DRIVER_ASSIGNED);
    }

    const outboxIds = [];
    for (const status of transitions) {
      const result = await this.bookingStatusService.transitionInTransaction(
        conn,
        bookingNumber,
        { status },
        actor,
        { skipAccessCheck: true },
      );
      if (result.outboxId) {
        outboxIds.push(result.outboxId);
      }
    }
    return outboxIds;
  }

  async assignDriver(bookingNumber, input, user) {
    const actor = this.actorFromUser(user);
    const conn = await this.pool.getConnection();
    const pendingOutboxIds = [];

    try {
      await conn.beginTransaction();

      const booking = await this.bookingRepository.findByBookingNumberForUpdate(
        conn,
        bookingNumber,
      );
      if (!booking) {
        throw new AppError("Booking not found", {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
        });
      }

      if (TERMINAL_ASSIGN_STATUSES.has(booking.status)) {
        throw new AppError("Booking cannot be assigned in the current status", {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.INVALID_STATUS_TRANSITION,
        });
      }

      const active = await this.bookingRepository.findActiveAssignmentForUpdate(
        conn,
        booking.id,
      );
      if (active) {
        throw new AppError("Booking already has an active driver assignment", {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.ALREADY_ASSIGNED,
        });
      }

      const driver = await this.ensureDriverEligible(conn, input.driverId);
      let driverVehicleId = input.driverVehicleId ?? null;
      if (!driverVehicleId) {
        const primaryVehicle = await this.driverRepository.findPrimaryVehicle(
          conn,
          driver.id,
        );
        driverVehicleId = primaryVehicle?.id ?? null;
      }

      const assignmentId = await this.bookingRepository.insertDriverAssignment(
        conn,
        {
          bookingId: booking.id,
          driverId: driver.id,
          driverVehicleId,
          assignedByUserId: actor.id,
          assignmentReason: input.assignmentReason ?? input.reason ?? null,
        },
      );

      const statusOutboxIds = await this.transitionToDriverAssigned(
        conn,
        bookingNumber,
        actor,
        booking.status,
      );
      pendingOutboxIds.push(...statusOutboxIds);

      if (this.chatService) {
        await this.chatService.syncAssignedParticipants(conn, {
          booking: {
            ...booking,
            status: BOOKING_STATUS.DRIVER_ASSIGNED,
          },
          driver,
          adminUser: user,
        });
      }

      await this.bookingRepository.insertActivityLog(conn, booking.id, {
        activityType: "DRIVER_ASSIGNED",
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

      if (this.outboxProcessor && pendingOutboxIds.length) {
        await this.outboxProcessor.dispatchOutboxIds(pendingOutboxIds);
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
      if (err.code === "ER_DUP_ENTRY") {
        throw new AppError("Assignment conflict", {
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
    let outboxId = null;
    let response;

    try {
      await conn.beginTransaction();

      const booking = await this.bookingRepository.findByBookingNumberForUpdate(
        conn,
        bookingNumber,
      );
      if (!booking) {
        throw new AppError("Booking not found", {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
        });
      }

      if (TERMINAL_REASSIGN_STATUSES.has(booking.status)) {
        throw new AppError(
          "Booking cannot be reassigned in the current status",
          {
            statusCode: HTTP_STATUS.CONFLICT,
            errorCode: ERROR_CODES.INVALID_STATUS_TRANSITION,
          },
        );
      }

      const active = await this.bookingRepository.findActiveAssignmentForUpdate(
        conn,
        booking.id,
      );
      if (!active) {
        throw new AppError("Booking has no active driver assignment", {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.NO_ACTIVE_ASSIGNMENT,
        });
      }

      if (Number(active.driver_id) === Number(input.driverId)) {
        throw new AppError("New driver must differ from the current driver", {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.VALIDATION_ERROR,
        });
      }

      const driver = await this.ensureDriverEligible(conn, input.driverId);
      let driverVehicleId = input.driverVehicleId ?? null;
      if (!driverVehicleId) {
        const primaryVehicle = await this.driverRepository.findPrimaryVehicle(
          conn,
          driver.id,
        );
        driverVehicleId = primaryVehicle?.id ?? null;
      }

      const deactivated = await this.bookingRepository.deactivateAssignment(
        conn,
        active.id,
        input.reason ?? null,
      );
      if (!deactivated) {
        throw new AppError("Assignment conflict", {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.ASSIGNMENT_CONFLICT,
        });
      }

      const assignmentId = await this.bookingRepository.insertDriverAssignment(
        conn,
        {
          bookingId: booking.id,
          driverId: driver.id,
          driverVehicleId,
          assignedByUserId: actor.id,
          assignmentReason: input.reason ?? input.assignmentReason ?? null,
        },
      );

      if (this.chatService) {
        const previousDriver = await this.driverRepository.findById(
          active.driver_id,
        );
        await this.chatService.syncAssignedParticipants(conn, {
          booking,
          driver,
          adminUser: user,
          previousDriverUserId: previousDriver?.user_id ?? null,
        });
      }

      await this.bookingRepository.insertActivityLog(conn, booking.id, {
        activityType: "DRIVER_REASSIGNED",
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

      if (this.outboxRepository) {
        outboxId = await this.outboxRepository.insertNotificationEvent(conn, {
          aggregateId: booking.id,
          eventType: EVENTS.DRIVER_REASSIGNED,
          payload: {
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
          },
        });
      }

      await conn.commit();

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
      if (err.code === "ER_DUP_ENTRY") {
        throw new AppError("Assignment conflict", {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.ASSIGNMENT_CONFLICT,
        });
      }
      throw err;
    } finally {
      conn.release();
    }

    if (outboxId && this.outboxProcessor) {
      await this.outboxProcessor.dispatchOutboxIds([outboxId]);
    }

    return response;
  }
}

module.exports = AdminDispatchService;

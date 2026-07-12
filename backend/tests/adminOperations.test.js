process.env.NODE_ENV = "test";
process.env.DB_USER = process.env.DB_USER || "test";
process.env.DB_NAME = process.env.DB_NAME || "ttaxi_test";
process.env.JWT_ACCESS_SECRET =
  process.env.JWT_ACCESS_SECRET || "test-access-secret-value";
process.env.JWT_REFRESH_SECRET =
  process.env.JWT_REFRESH_SECRET || "test-refresh-secret-value";

const { test } = require("node:test");
const assert = require("node:assert/strict");
const jwt = require("jsonwebtoken");
const request = require("supertest");
const AdminOperationsService = require("../src/services/adminOperations.service");
const AdminDispatchService = require("../src/services/adminDispatch.service");
const BookingRepository = require("../src/repositories/booking.repository");
const DriverCandidateScoringService = require("../src/services/driverCandidateScoring.service");
const container = require("../src/helpers/container");
const app = require("../src/app");
const ERROR_CODES = require("../src/constants/errorCodes");
const { ADMIN_BOOKING_VIEWS } = require("../src/constants/adminOperations.constants");

const settlementStub = {
  async driverHasBlockingSettlement() {
    return false;
  },
};

function sign(role = "ADMIN", id = 1) {
  return jwt.sign(
    {
      sub: id,
      email: `${role.toLowerCase()}@example.com`,
      role,
      type: "access",
    },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: "1h" },
  );
}

function fixedNow() {
  return new Date("2026-07-11T10:00:00+07:00");
}

test("AdminOperationsService defaults view to needs_action", () => {
  const service = new AdminOperationsService(() => fixedNow());
  const filters = service.buildFilters({});
  assert.equal(filters.view, ADMIN_BOOKING_VIEWS.NEEDS_ACTION);
  assert.equal(filters.needsActionOnly, true);
  assert.equal(filters.excludeTerminalStatuses, true);
});

test("AdminOperationsService rejects invalid view", () => {
  const service = new AdminOperationsService(() => fixedNow());
  const filters = service.buildFilters({ view: "invalid" });
  assert.equal(filters.invalidView, true);
});

test("completed tab applies 30-day history range", () => {
  const service = new AdminOperationsService(() => fixedNow());
  const filters = service.buildFilters({ view: ADMIN_BOOKING_VIEWS.COMPLETED });
  assert.equal(filters.status, "COMPLETED");
  assert.ok(filters.serviceDateFrom);
  assert.ok(filters.serviceDateTo);
});

test("evaluateOperations marks overdue unassigned as urgent", () => {
  const service = new AdminOperationsService(() => fixedNow());
  const ops = service.evaluateOperations({
    status: "PENDING",
    scheduled_pickup_at: "2026-07-11 08:00:00",
    driver_id: null,
    assignment_id: null,
    updated_at: "2026-07-11 08:00:00",
  });
  assert.equal(ops.severity, "URGENT");
  assert.equal(ops.primaryActionReason, "PICKUP_OVERDUE_UNASSIGNED");
  assert.equal(ops.primaryCta, "ASSIGN_DRIVER");
  assert.equal(ops.needsAction, true);
});

test("evaluateOperations keeps a four-hour-future unassigned booking out of needs action", () => {
  const service = new AdminOperationsService(() => fixedNow());
  const ops = service.evaluateOperations({
    status: "PENDING",
    scheduled_pickup_at: "2026-07-11 14:00:00",
    driver_id: null,
    assignment_id: null,
    updated_at: "2026-07-11 10:00:00",
  });
  assert.equal(ops.needsAction, false);
  assert.equal(ops.primaryActionReason, null);
});

test("evaluateOperations includes a 30-minute-future unassigned booking in needs action", () => {
  const service = new AdminOperationsService(() => fixedNow());
  const ops = service.evaluateOperations({
    status: "PENDING",
    scheduled_pickup_at: "2026-07-11 10:30:00",
    driver_id: null,
    assignment_id: null,
    updated_at: "2026-07-11 10:00:00",
  });
  assert.equal(ops.needsAction, true);
  assert.equal(ops.primaryActionReason, "PICKUP_SOON_UNASSIGNED");
});

test("evaluateOperations marks low rating as urgent", () => {
  const service = new AdminOperationsService(() => fixedNow());
  const ops = service.evaluateOperations({
    status: "COMPLETED",
    scheduled_pickup_at: "2026-07-10 08:00:00",
    driver_id: 3,
    assignment_id: 9,
    updated_at: "2026-07-10 12:00:00",
    review_rating: 1,
  });
  assert.equal(ops.severity, "URGENT");
  assert.equal(ops.primaryActionReason, "LOW_RATING");
  assert.equal(ops.primaryCta, "REVIEW_RATING");
});

test("evaluateOperations marks receipt submitted for settlement review", () => {
  const service = new AdminOperationsService(() => fixedNow());
  const ops = service.evaluateOperations({
    status: "SETTLEMENT_PENDING",
    scheduled_pickup_at: "2026-07-10 08:00:00",
    driver_id: 3,
    assignment_id: 9,
    commission_status: "DUE",
    commission_receipt_file_id: 44,
    updated_at: "2026-07-10 12:00:00",
  });
  assert.equal(ops.primaryActionReason, "RECEIPT_REVIEW");
  assert.equal(ops.primaryCta, "CONFIRM_SETTLEMENT");
  assert.equal(ops.settlementState, "RECEIPT_SUBMITTED");
});

test("evaluateOperations marks receipt missing without approve CTA path", () => {
  const service = new AdminOperationsService(() => fixedNow());
  const ops = service.evaluateOperations({
    status: "SETTLEMENT_PENDING",
    scheduled_pickup_at: "2026-07-10 08:00:00",
    driver_id: 3,
    assignment_id: 9,
    commission_status: "DUE",
    commission_receipt_file_id: null,
    metadata: null,
    updated_at: "2026-07-10 12:00:00",
  });
  assert.equal(ops.primaryActionReason, "RECEIPT_MISSING");
  assert.equal(ops.primaryCta, "SETTLEMENT_DETAIL");
  assert.equal(ops.settlementState, "RECEIPT_MISSING");
});

test("evaluateOperations keeps rejected receipt out of approve CTA path", () => {
  const service = new AdminOperationsService(() => fixedNow());
  const ops = service.evaluateOperations({
    status: "SETTLEMENT_PENDING",
    scheduled_pickup_at: "2026-07-10 08:00:00",
    driver_id: 3,
    assignment_id: 9,
    commission_status: "DUE",
    commission_receipt_file_id: null,
    metadata: JSON.stringify({ commissionRejectionReason: "Unreadable slip" }),
    updated_at: "2026-07-10 12:00:00",
  });
  assert.equal(ops.primaryActionReason, "RECEIPT_REJECTED");
  assert.equal(ops.primaryCta, "SETTLEMENT_DETAIL");
  assert.equal(ops.settlementState, "RECEIPT_REJECTED");
});

test("sortQueueItems orders urgent before review", () => {
  const service = new AdminOperationsService(() => fixedNow());
  const dispatch = new AdminDispatchService(
    {},
    {},
    {},
    {},
    settlementStub,
    null,
    null,
    new DriverCandidateScoringService(),
  );
  const urgent = dispatch.mapQueueItem({
    booking_number: "TX2",
    status: "PENDING",
    scheduled_pickup_at: "2026-07-11 08:00:00",
    driver_id: null,
    updated_at: "2026-07-11 08:00:00",
    adults: 1,
    total_amount: 100,
    currency: "THB",
    is_new_booking: 1,
  });
  const review = dispatch.mapQueueItem({
    booking_number: "TX1",
    status: "DRIVER_ARRIVED",
    scheduled_pickup_at: "2026-07-11 11:00:00",
    driver_id: 2,
    assignment_id: 1,
    updated_at: "2026-07-11 08:00:00",
    adults: 1,
    total_amount: 100,
    currency: "THB",
    is_new_booking: 0,
  });
  const sorted = service.sortQueueItems([review, urgent]);
  assert.equal(sorted[0].bookingNumber, "TX2");
});

test("ADMIN can fetch bookings summary", async () => {
  container.register("adminDispatchService", () => ({
    async getBookingsSummary() {
      return {
        needsAction: 3,
        unassigned: 1,
        today: 5,
        inProgress: 2,
        settlementPending: 4,
        issues: 1,
      };
    },
  }));

  const res = await request(app)
    .get("/api/v1/admin/bookings/summary")
    .set("Authorization", `Bearer ${sign("ADMIN")}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.data.needsAction, 3);
});

test("list bookings rejects invalid view", async () => {
  container.register("adminDispatchService", () => ({
    async listBookings(query) {
      const service = new AdminOperationsService(() => fixedNow());
      const filters = service.buildFilters(query);
      if (filters.invalidView) {
        const AppError = require("../src/utils/AppError");
        throw new AppError("Invalid booking view", { statusCode: 400 });
      }
      return { page: 1, pageSize: 20, total: 0, view: filters.view, items: [] };
    },
  }));

  const res = await request(app)
    .get("/api/v1/admin/bookings?view=bad")
    .set("Authorization", `Bearer ${sign("ADMIN")}`);

  assert.equal(res.status, 400);
});

test("CUSTOMER cannot access bookings summary", async () => {
  const res = await request(app)
    .get("/api/v1/admin/bookings/summary")
    .set("Authorization", `Bearer ${sign("CUSTOMER", 8)}`);
  assert.equal(res.status, 403);
  assert.equal(res.body.error_code, ERROR_CODES.FORBIDDEN);
});

test("search trim skips blank query in filters", () => {
  const service = new AdminOperationsService(() => fixedNow());
  const filters = service.buildFilters({ view: ADMIN_BOOKING_VIEWS.TODAY, search: "   " });
  assert.equal(filters.search, null);
});

test("resolveAdminUserId returns numeric admin id", () => {
  const service = new AdminOperationsService(() => fixedNow());
  assert.equal(service.resolveAdminUserId({ id: 7 }), 7);
  assert.equal(service.resolveAdminUserId({ id: "9" }), 9);
  assert.equal(service.resolveAdminUserId(null), null);
  assert.equal(service.resolveAdminUserId({}), null);
});

test("issues summary filter uses issues view not needs_action", () => {
  const service = new AdminOperationsService(() => fixedNow());
  const filters = service.buildSummaryFilter("issues", 3);
  assert.equal(filters.view, ADMIN_BOOKING_VIEWS.ISSUES);
  assert.equal(filters.issuesOnly, true);
  assert.equal(filters.adminUserId, 3);
  assert.notEqual(filters.needsActionOnly, true);
});

test("issues SQL is narrower than needs action SQL", () => {
  const repo = new BookingRepository({});
  const service = new AdminOperationsService(() => fixedNow());
  const needsFilters = service.buildFilters(
    { view: ADMIN_BOOKING_VIEWS.NEEDS_ACTION },
    1,
  );
  const issueFilters = service.buildFilters(
    { view: ADMIN_BOOKING_VIEWS.ISSUES },
    1,
  );
  const needs = repo.buildAdminBookingFilters(needsFilters);
  const issues = repo.buildAdminBookingFilters(issueFilters);
  assert.match(needs.whereSql, /commission_receipt_file_id IS NOT NULL/);
  assert.doesNotMatch(issues.whereSql, /commission_receipt_file_id IS NOT NULL/);
  assert.match(needs.whereSql, /scheduled_pickup_at <= \?/);
  assert.doesNotMatch(issues.whereSql, /scheduled_pickup_at <= \?/);
});

test("needs action settlement conditions require DUE or OVERDUE", () => {
  const repo = new BookingRepository({});
  const where = repo.buildNeedsActionWhere({
    operationsNow: "2026-07-11 10:00:00",
    operationsUrgentCutoff: "2026-07-11 10:30:00",
    adminUserId: 1,
  });
  assert.match(where.sql, /commission_status IN \('DUE', 'OVERDUE'\)/);
});

test("admin unread is excluded from needs_action when admin id missing", () => {
  const repo = new BookingRepository({});
  const where = repo.buildNeedsActionWhere({
    operationsNow: "2026-07-11 10:00:00",
    operationsUrgentCutoff: "2026-07-11 10:30:00",
    adminUserId: null,
  });
  assert.doesNotMatch(where.sql, /chat_participants/);
});

test("admin unread is included when admin id is present", () => {
  const repo = new BookingRepository({});
  const where = repo.buildNeedsActionWhere({
    operationsNow: "2026-07-11 10:00:00",
    operationsUrgentCutoff: "2026-07-11 10:30:00",
    adminUserId: 5,
  });
  assert.match(where.sql, /chat_participants/);
});

test("list and count filters share buildAdminBookingFilters", () => {
  const repo = new BookingRepository({});
  const service = new AdminOperationsService(() => fixedNow());
  const filters = service.buildFilters(
    { view: ADMIN_BOOKING_VIEWS.TODAY, search: "Kim", driverId: "4" },
    2,
  );
  const built = repo.buildAdminBookingFilters(filters);
  assert.ok(built.whereSql.includes("b.deleted_at IS NULL"));
  assert.ok(built.whereSql.includes("st.code = ?") === false);
  assert.ok(built.whereSql.includes("b.scheduled_pickup_at >="));
  assert.ok(built.params.length > 0);
  assert.equal(filters.adminUserId, 2);
});

test("evaluateOperations exposes adminUnreadCount from row", () => {
  const service = new AdminOperationsService(() => fixedNow());
  const ops = service.evaluateOperations({
    status: "DRIVER_ASSIGNED",
    scheduled_pickup_at: "2026-07-11 12:00:00",
    driver_id: 2,
    assignment_id: 1,
    updated_at: "2026-07-11 10:00:00",
    admin_unread_count: 2,
  });
  assert.equal(ops.adminUnreadCount, 2);
  assert.equal(ops.hasUnreadInquiry, true);
  assert.equal(ops.primaryActionReason, "CUSTOMER_INQUIRY");
});

test("evaluateOperations hides unread inquiry when count is zero", () => {
  const service = new AdminOperationsService(() => fixedNow());
  const ops = service.evaluateOperations({
    status: "DRIVER_ASSIGNED",
    scheduled_pickup_at: "2026-07-11 12:00:00",
    driver_id: 2,
    assignment_id: 1,
    updated_at: "2026-07-11 10:00:00",
    admin_unread_count: 0,
  });
  assert.equal(ops.hasUnreadInquiry, false);
  assert.equal(ops.actionReasons.includes("CUSTOMER_INQUIRY"), false);
});

test("paid commission is not treated as receipt submitted", () => {
  const service = new AdminOperationsService(() => fixedNow());
  const ops = service.evaluateOperations({
    status: "SETTLEMENT_PENDING",
    scheduled_pickup_at: "2026-07-10 08:00:00",
    driver_id: 3,
    assignment_id: 9,
    commission_status: "PAID",
    commission_receipt_file_id: 44,
    updated_at: "2026-07-10 12:00:00",
  });
  assert.equal(ops.settlementState, "ADMIN_CONFIRMED");
  assert.equal(ops.primaryActionReason, null);
  assert.equal(ops.primaryCta, "VIEW_BOOKING");
});

test("count query uses COUNT DISTINCT booking id", async () => {
  let countSql = null;
  const repo = new BookingRepository({
    async query(sql) {
      countSql = sql;
      return [[{ total: 3 }]];
    },
  });
  const service = new AdminOperationsService(() => fixedNow());
  const filters = service.buildFilters({ view: ADMIN_BOOKING_VIEWS.TODAY }, 1);
  const total = await repo.countAdminBookings(filters);
  assert.equal(total, 3);
  assert.ok(countSql.includes("COUNT(DISTINCT b.id)"));
});

test("getBookingDetail uses actor for unread count", async () => {
  let unreadArgs = null;
  const bookingRepository = {
    async findAdminBookingDetail() {
      return {
        id: 10,
        booking_number: "TX1",
        status: "DRIVER_ASSIGNED",
        scheduled_pickup_at: "2026-07-11 12:00:00",
        driver_id: 2,
        commission_status: "NOT_DUE_YET",
        commission_receipt_file_id: null,
        metadata: null,
        updated_at: "2026-07-11 10:00:00",
        service_type_code: "AIRPORT_PICKUP",
        service_type_name: "Pickup",
      };
    },
    async findChargeItemsByBookingId() {
      return [];
    },
    async findStatusLogsByBookingId() {
      return [];
    },
    async findAssignmentsByBookingId() {
      return [{ id: 1, is_active: 1, driver_id: 2 }];
    },
    async countAdminUnreadForBooking(adminUserId, bookingId) {
      unreadArgs = { adminUserId, bookingId };
      return 2;
    },
  };
  const dispatch = new AdminDispatchService(
    {},
    bookingRepository,
    {},
    {},
    settlementStub,
    null,
    null,
    new DriverCandidateScoringService(),
    null,
    null,
    null,
  );
  const detail = await dispatch.getBookingDetail("TX1", { id: 5, role: "ADMIN" });
  assert.deepEqual(unreadArgs, { adminUserId: 5, bookingId: 10 });
  assert.equal(detail.operations.adminUnreadCount, 2);
  assert.equal(detail.operations.hasUnreadInquiry, true);
});

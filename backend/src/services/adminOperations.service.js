const BOOKING_STATUS = require('../constants/reservationStatus');
const {
  ADMIN_BOOKING_VIEWS,
  OPERATIONS_SEVERITY,
  OPERATIONS_THRESHOLDS,
  DEFAULT_HISTORY_DAYS,
  TERMINAL_BOOKING_STATUSES,
  ACTIVE_OPERATING_STATUSES,
  PRE_PICKUP_STATUSES,
} = require('../constants/adminOperations.constants');
const {
  SERVICE_TIME_ZONE,
  parseServiceDateTimeToMs,
  getElapsedMsSinceServiceDateTime,
} = require('../utils/serviceDateTime.util');

const VALID_VIEWS = new Set(Object.values(ADMIN_BOOKING_VIEWS));

const SETTLEMENT_FILTER_STATUSES = new Set([
  'RECEIPT_REJECTED',
  'RECEIPT_SUBMITTED',
  'RECEIPT_MISSING',
  'ADMIN_CONFIRMED',
]);

class AdminOperationsService {
  constructor(now = () => new Date()) {
    this.now = now;
  }

  thailandDateParts(date) {
    const parts = new Intl.DateTimeFormat('en-CA', {
      timeZone: SERVICE_TIME_ZONE,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).formatToParts(date);
    const part = (type) => parts.find((item) => item.type === type)?.value;
    return {
      year: Number(part('year')),
      month: Number(part('month')),
      day: Number(part('day')),
      date: `${part('year')}-${part('month')}-${part('day')}`,
    };
  }

  formatThailandDateTime(value) {
    const date = value instanceof Date ? value : new Date(value);
    const parts = new Intl.DateTimeFormat('en-US', {
      timeZone: SERVICE_TIME_ZONE,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hourCycle: 'h23',
      hour12: false,
    }).formatToParts(date);
    const part = (type) => parts.find((item) => item.type === type)?.value;
    const hour = part('hour') === '24' ? '00' : part('hour');
    return `${part('year')}-${part('month')}-${part('day')} ${hour}:${part('minute')}:${part('second')}`;
  }

  serviceDayRange(date = this.now()) {
    const parts = this.thailandDateParts(date);
    const next = new Date(Date.UTC(parts.year, parts.month - 1, parts.day + 1));
    const nextParts = this.thailandDateParts(next);
    return {
      date: parts.date,
      start: `${parts.date} 00:00:00`,
      end: `${nextParts.date} 00:00:00`,
    };
  }

  historyRange(days = DEFAULT_HISTORY_DAYS, date = this.now()) {
    const endRange = this.serviceDayRange(date);
    const startDate = new Date(date);
    startDate.setDate(startDate.getDate() - days);
    const startParts = this.thailandDateParts(startDate);
    return {
      serviceDateFrom: `${startParts.date} 00:00:00`,
      serviceDateTo: endRange.end,
    };
  }

  parseView(query) {
    const raw = query.view?.trim();
    if (!raw) return ADMIN_BOOKING_VIEWS.NEEDS_ACTION;
    if (!VALID_VIEWS.has(raw)) return null;
    return raw;
  }

  parseExtendedFilters(query) {
    const view = this.parseView(query);
    const lowRatingRaw = query.lowRating ?? query.low_rating;
    const unassignedRaw = query.unassigned;
    const hasInquiryRaw = query.hasInquiry ?? query.has_inquiry;

    return {
      view,
      search: query.search?.trim() || null,
      status: query.status || null,
      driverId: query.driverId ? Number(query.driverId) : null,
      assignmentState: query.assignmentState || null,
      serviceDateFrom: null,
      serviceDateTo: null,
      serviceType: query.serviceType?.trim() || query.service_type?.trim() || null,
      origin: query.origin?.trim() || null,
      destination: query.destination?.trim() || null,
      settlementStatus: query.settlementStatus?.trim() || query.settlement_status?.trim() || null,
      lowRating:
        lowRatingRaw === 'true' || lowRatingRaw === true || lowRatingRaw === '1',
      unassigned:
        unassignedRaw === 'true' || unassignedRaw === true || unassignedRaw === '1',
      hasInquiry:
        hasInquiryRaw === 'true' || hasInquiryRaw === true || hasInquiryRaw === '1',
      adminUserId: null,
    };
  }

  applyDateQuery(filters, query) {
    const from = query.serviceDateFrom || query.dateFrom;
    const to = query.serviceDateTo || query.dateTo;
    if (from) {
      filters.serviceDateFrom = `${from} 00:00:00`;
    }
    if (to) {
      const end = new Date(`${to}T00:00:00`);
      end.setDate(end.getDate() + 1);
      const nextParts = this.thailandDateParts(end);
      filters.serviceDateTo = `${nextParts.date} 00:00:00`;
    }
    return filters;
  }

  applyViewDefaults(filters, view = ADMIN_BOOKING_VIEWS.NEEDS_ACTION) {
    const now = this.now();
    const today = this.serviceDayRange(now);
    const history = this.historyRange(DEFAULT_HISTORY_DAYS, now);
    const nowText = this.formatThailandDateTime(now);
    const urgentCutoff = this.formatThailandDateTime(
      new Date(now.getTime() + OPERATIONS_THRESHOLDS.UNASSIGNED_URGENT_BEFORE_MS),
    );

    const next = { ...filters, view, operationsNow: nowText, operationsUrgentCutoff: urgentCutoff };

    switch (view) {
      case ADMIN_BOOKING_VIEWS.NEEDS_ACTION:
        next.excludeTerminalStatuses = true;
        next.needsActionOnly = true;
        break;
      case ADMIN_BOOKING_VIEWS.ISSUES:
        next.issuesOnly = true;
        break;
      case ADMIN_BOOKING_VIEWS.TODAY:
        next.excludeTerminalStatuses = true;
        if (!next.serviceDateFrom) next.serviceDateFrom = today.start;
        if (!next.serviceDateTo) next.serviceDateTo = today.end;
        break;
      case ADMIN_BOOKING_VIEWS.UPCOMING:
        next.excludeTerminalStatuses = true;
        if (!next.serviceDateFrom) next.serviceDateFrom = today.end;
        break;
      case ADMIN_BOOKING_VIEWS.IN_PROGRESS:
        next.excludeTerminalStatuses = true;
        next.inProgressOnly = true;
        break;
      case ADMIN_BOOKING_VIEWS.SETTLEMENT:
        next.status = BOOKING_STATUS.SETTLEMENT_PENDING;
        break;
      case ADMIN_BOOKING_VIEWS.COMPLETED:
        next.status = BOOKING_STATUS.COMPLETED;
        if (!next.serviceDateFrom) next.serviceDateFrom = history.serviceDateFrom;
        if (!next.serviceDateTo) next.serviceDateTo = history.serviceDateTo;
        break;
      case ADMIN_BOOKING_VIEWS.CANCELLED:
        next.cancelledTab = true;
        if (!next.serviceDateFrom) next.serviceDateFrom = history.serviceDateFrom;
        if (!next.serviceDateTo) next.serviceDateTo = history.serviceDateTo;
        break;
      case ADMIN_BOOKING_VIEWS.ALL:
        if (!next.serviceDateFrom) next.serviceDateFrom = history.serviceDateFrom;
        if (!next.serviceDateTo) next.serviceDateTo = history.serviceDateTo;
        break;
      default:
        break;
    }

    if (
      next.settlementStatus &&
      !SETTLEMENT_FILTER_STATUSES.has(next.settlementStatus)
    ) {
      next.settlementStatus = null;
    }

    return next;
  }

  resolveAdminUserId(actorUser) {
    const id = actorUser?.id;
    if (id == null || !Number.isFinite(Number(id))) return null;
    return Number(id);
  }

  buildFilters(query, adminUserId = null) {
    const view = this.parseView(query);
    if (view == null) {
      return { invalidView: true };
    }

    let filters = this.parseExtendedFilters(query);
    filters = this.applyDateQuery(filters, query);
    filters.view = view;
    filters.adminUserId = adminUserId;
    return this.applyViewDefaults(filters, view);
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

  isUnassigned(row) {
    return row.driver_id == null && !row.assignment_id;
  }

  hasReceiptRejected(row) {
    const metadata = this.parseMetadata(row.metadata);
    return (
      row.status === BOOKING_STATUS.SETTLEMENT_PENDING &&
      ['DUE', 'OVERDUE'].includes(row.commission_status) &&
      metadata?.commissionRejectionReason &&
      !row.commission_receipt_file_id
    );
  }

  hasReceiptSubmitted(row) {
    return (
      row.status === BOOKING_STATUS.SETTLEMENT_PENDING &&
      ['DUE', 'OVERDUE'].includes(row.commission_status) &&
      row.commission_receipt_file_id
    );
  }

  hasReceiptMissing(row) {
    return (
      row.status === BOOKING_STATUS.SETTLEMENT_PENDING &&
      ['DUE', 'OVERDUE'].includes(row.commission_status) &&
      !row.commission_receipt_file_id &&
      !this.hasReceiptRejected(row)
    );
  }

  isLowRating(row) {
    const rating = row.review_rating != null ? Number(row.review_rating) : null;
    return rating != null && rating <= 2;
  }

  hasAdminUnread(row) {
    return Number(row.admin_unread_count ?? 0) > 0;
  }

  pickupMs(row) {
    return parseServiceDateTimeToMs(row.scheduled_pickup_at);
  }

  evaluateReasons(row, nowMs = this.now().getTime()) {
    const reasons = [];
    const status = row.status;
    const pickupMs = this.pickupMs(row);
    const nowText = this.formatThailandDateTime(new Date(nowMs));
    const urgentCutoffMs =
      nowMs + OPERATIONS_THRESHOLDS.UNASSIGNED_URGENT_BEFORE_MS;
    const unassigned = this.isUnassigned(row);

    if (this.isLowRating(row)) {
      reasons.push({
        code: 'LOW_RATING',
        severity: OPERATIONS_SEVERITY.URGENT,
        priority: 10,
      });
    }

    if (this.hasReceiptRejected(row)) {
      reasons.push({
        code: 'RECEIPT_REJECTED',
        severity: OPERATIONS_SEVERITY.URGENT,
        priority: 20,
      });
    }

    if (pickupMs != null && pickupMs < nowMs && unassigned) {
      reasons.push({
        code: 'PICKUP_OVERDUE_UNASSIGNED',
        severity: OPERATIONS_SEVERITY.URGENT,
        priority: 30,
      });
    }

    if (
      pickupMs != null &&
      pickupMs < nowMs &&
      PRE_PICKUP_STATUSES.includes(status)
    ) {
      reasons.push({
        code: 'PICKUP_OVERDUE_STALLED',
        severity: OPERATIONS_SEVERITY.URGENT,
        priority: 40,
      });
    }

    if (this.hasAdminUnread(row)) {
      reasons.push({
        code: 'CUSTOMER_INQUIRY',
        severity: OPERATIONS_SEVERITY.URGENT,
        priority: 50,
      });
    }

    if (
      pickupMs != null &&
      pickupMs >= nowMs &&
      pickupMs <= urgentCutoffMs &&
      unassigned
    ) {
      reasons.push({
        code: 'PICKUP_SOON_UNASSIGNED',
        severity: OPERATIONS_SEVERITY.SOON,
        priority: 110,
      });
    }

    if (this.hasReceiptSubmitted(row)) {
      reasons.push({
        code: 'RECEIPT_REVIEW',
        severity: OPERATIONS_SEVERITY.SOON,
        priority: 120,
      });
    }

    if (this.hasReceiptMissing(row)) {
      reasons.push({
        code: 'RECEIPT_MISSING',
        severity: OPERATIONS_SEVERITY.SOON,
        priority: 130,
      });
    }

    if (status === BOOKING_STATUS.DRIVER_ARRIVED) {
      const elapsed = getElapsedMsSinceServiceDateTime(row.updated_at, nowMs);
      if (
        elapsed != null &&
        elapsed >= OPERATIONS_THRESHOLDS.DRIVER_ARRIVED_PICKUP_DELAY_MS
      ) {
        reasons.push({
          code: 'BOARDING_DELAY',
          severity: OPERATIONS_SEVERITY.REVIEW,
          priority: 210,
        });
      }
    }

    if (status === BOOKING_STATUS.PICKED_UP) {
      const elapsed = getElapsedMsSinceServiceDateTime(row.updated_at, nowMs);
      if (
        elapsed != null &&
        elapsed >= OPERATIONS_THRESHOLDS.PICKED_UP_LONG_TRIP_MS
      ) {
        reasons.push({
          code: 'LONG_TRIP',
          severity: OPERATIONS_SEVERITY.REVIEW,
          priority: 220,
        });
      }
    }

    if (!TERMINAL_BOOKING_STATUSES.includes(status) && status !== BOOKING_STATUS.SETTLEMENT_PENDING) {
      const elapsed = getElapsedMsSinceServiceDateTime(row.updated_at, nowMs);
      if (
        elapsed != null &&
        elapsed >= OPERATIONS_THRESHOLDS.STATUS_STALE_MS &&
        !ACTIVE_OPERATING_STATUSES.includes(status)
      ) {
        reasons.push({
          code: 'STATUS_STALE',
          severity: OPERATIONS_SEVERITY.REVIEW,
          priority: 230,
        });
      }
    }

    reasons.sort((a, b) => a.priority - b.priority);
    return { reasons, nowText };
  }

  severityRank(severity) {
    if (severity === OPERATIONS_SEVERITY.URGENT) return 0;
    if (severity === OPERATIONS_SEVERITY.SOON) return 1;
    return 2;
  }

  evaluateOperations(row, nowMs = this.now().getTime()) {
    const { reasons } = this.evaluateReasons(row, nowMs);
    const primary = reasons[0] ?? null;
    const severity = primary?.severity ?? null;
    const extraCount = reasons.length > 1 ? reasons.length - 1 : 0;

    return {
      severity,
      priority: primary?.priority ?? 999,
      actionReasons: reasons.map((item) => item.code),
      primaryActionReason: primary?.code ?? null,
      extraActionReasonCount: extraCount,
      needsAction: reasons.length > 0,
      nextAction: this.buildNextAction(row, primary),
      primaryCta: this.buildPrimaryCta(row, primary),
      settlementState: this.mapSettlementState(row),
      lowRating: this.isLowRating(row),
      adminUnreadCount: Number(row.admin_unread_count ?? 0),
      hasUnreadInquiry: this.hasAdminUnread(row),
    };
  }

  mapSettlementState(row) {
    if (row.status !== BOOKING_STATUS.SETTLEMENT_PENDING) return null;
    if (this.hasReceiptRejected(row)) return 'RECEIPT_REJECTED';
    if (row.commission_status === 'PAID') return 'ADMIN_CONFIRMED';
    if (this.hasReceiptSubmitted(row)) return 'RECEIPT_SUBMITTED';
    return 'RECEIPT_MISSING';
  }

  buildPrimaryCta(row, primaryReason) {
    const status = row.status;
    if (!primaryReason) {
      if (status === BOOKING_STATUS.COMPLETED || status === BOOKING_STATUS.CANCELLED || status === BOOKING_STATUS.NO_SHOW) {
        return 'VIEW_BOOKING';
      }
      if (ACTIVE_OPERATING_STATUSES.includes(status)) {
        return 'CHECK_STATUS';
      }
      return 'VIEW_BOOKING';
    }

    switch (primaryReason.code) {
      case 'LOW_RATING':
        return 'REVIEW_RATING';
      case 'RECEIPT_REJECTED':
        return 'SETTLEMENT_DETAIL';
      case 'RECEIPT_REVIEW':
        return 'CONFIRM_SETTLEMENT';
      case 'RECEIPT_MISSING':
        return 'SETTLEMENT_DETAIL';
      case 'PICKUP_OVERDUE_UNASSIGNED':
      case 'PICKUP_SOON_UNASSIGNED':
        return 'ASSIGN_DRIVER';
      case 'CUSTOMER_INQUIRY':
        return 'OPEN_CHAT';
      default:
        if (this.isUnassigned(row) && !TERMINAL_BOOKING_STATUSES.includes(status)) {
          return 'ASSIGN_DRIVER';
        }
        if (this.hasReceiptSubmitted(row)) return 'CONFIRM_SETTLEMENT';
        if (status === BOOKING_STATUS.SETTLEMENT_PENDING) return 'SETTLEMENT_DETAIL';
        return 'VIEW_BOOKING';
    }
  }

  buildNextAction(row, primaryReason) {
    const status = row.status;
    if (!primaryReason) {
      if (this.isUnassigned(row) && !TERMINAL_BOOKING_STATUSES.includes(status)) {
        return { code: 'ASSIGN_DRIVER', params: {} };
      }
      if (this.hasReceiptSubmitted(row)) {
        return { code: 'CONFIRM_SETTLEMENT', params: {} };
      }
      if (status === BOOKING_STATUS.SETTLEMENT_PENDING) {
        return { code: 'AWAIT_RECEIPT', params: {} };
      }
      return { code: 'MONITOR', params: {} };
    }
    return { code: primaryReason.code, params: {} };
  }

  sortQueueItems(items) {
    return [...items].sort((a, b) => {
      const opsA = a.operations ?? {};
      const opsB = b.operations ?? {};
      const sevDiff =
        this.severityRank(opsA.severity) - this.severityRank(opsB.severity);
      if (sevDiff !== 0) return sevDiff;
      const priDiff = (opsA.priority ?? 999) - (opsB.priority ?? 999);
      if (priDiff !== 0) return priDiff;
      const pickupA = parseServiceDateTimeToMs(a.scheduledPickupAt) ?? Number.MAX_SAFE_INTEGER;
      const pickupB = parseServiceDateTimeToMs(b.scheduledPickupAt) ?? Number.MAX_SAFE_INTEGER;
      if (pickupA !== pickupB) return pickupA - pickupB;
      return String(a.bookingNumber).localeCompare(String(b.bookingNumber));
    });
  }

  summaryViewKeys() {
    return [
      ADMIN_BOOKING_VIEWS.NEEDS_ACTION,
      'unassigned',
      ADMIN_BOOKING_VIEWS.TODAY,
      ADMIN_BOOKING_VIEWS.IN_PROGRESS,
      ADMIN_BOOKING_VIEWS.SETTLEMENT,
      'issues',
    ];
  }

  buildSummaryFilter(viewKey, adminUserId = null) {
    if (viewKey === 'unassigned') {
      const history = this.historyRange();
      const filters = this.buildFilters(
        {
          view: ADMIN_BOOKING_VIEWS.ALL,
          unassigned: 'true',
          serviceDateFrom: history.serviceDateFrom.slice(0, 10),
          serviceDateTo: history.serviceDateTo.slice(0, 10),
        },
        adminUserId,
      );
      filters.excludeTerminalStatuses = true;
      filters.assignmentState = 'UNASSIGNED';
      filters.needsActionOnly = false;
      return filters;
    }
    if (viewKey === 'issues') {
      return this.buildFilters(
        { view: ADMIN_BOOKING_VIEWS.ISSUES },
        adminUserId,
      );
    }
    return this.buildFilters({ view: viewKey }, adminUserId);
  }
}

module.exports = AdminOperationsService;

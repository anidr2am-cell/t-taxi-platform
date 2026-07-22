process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const jwt = require('jsonwebtoken');
const request = require('supertest');

const BOOKING_STATUS = require('../src/constants/reservationStatus');
const COMMISSION_STATUS = require('../src/constants/commissionStatus');
const ERROR_CODES = require('../src/constants/errorCodes');
const { hashToken } = require('../src/utils/tokenHash.util');
const AdminDispatchService = require('../src/services/adminDispatch.service');
const DriverTripFlowService = require('../src/services/driverTripFlow.service');
const DriverQrService = require('../src/services/driverQr.service');
const DriverJobService = require('../src/services/driverJob.service');
const BookingStatusService = require('../src/services/bookingStatus.service');
const CommissionSettlementService = require('../src/services/commissionSettlement.service');
const ReviewService = require('../src/services/review.service');
const ChatService = require('../src/services/chat.service');
const container = require('../src/helpers/container');
const app = require('../src/app');
const { uploadDir } = require('../src/config/multer');

const BOOKING_NUMBER = 'TX202607010001';
const GUEST_TOKEN = 'guest-access-token-mvp';
const DRIVER_USER_ID = 44;
const OLD_DRIVER_USER_ID = 99;
const ADMIN_USER = { id: 1, role: 'ADMIN' };

function sign(role, id) {
  return jwt.sign(
    { sub: id, email: `${role.toLowerCase()}@example.com`, role, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

function connStub(state) {
  return {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
    async query(sql, params) {
      if (sql.includes('FROM bookings') && params?.[0] === state.bookingId) {
        const row = bookingRow(state);
        return [[{
          id: row.id,
          booking_number: row.booking_number,
          status: row.status,
          total_amount: row.total_amount,
          currency: row.currency,
          commission_status: row.commission_status,
          commission_amount: row.commission_amount,
          completed_at: row.completed_at,
          driver_id: row.driver_id,
        }]];
      }
      return [[]];
    },
  };
}

function createLifecycleState() {
  return {
    bookingId: 10,
    bookingNumber: BOOKING_NUMBER,
    status: BOOKING_STATUS.PENDING,
    totalAmount: 1200,
    currency: 'THB',
    customerName: 'Kim',
    customerUserId: null,
    driverUserId: null,
    activeDriverUserId: null,
    guestTokenHash: hashToken(GUEST_TOKEN),
    boardingToken: 'boarding-qr-token',
    dropoffToken: 'dropoff-qr-token',
    commissionStatus: COMMISSION_STATUS.NOT_DUE_YET,
    commissionAmount: null,
    commissionReceiptFileId: null,
    commissionMetadata: {},
    storedReceiptPath: null,
    commissionUpdates: 0,
    reviewId: null,
    reviewCount: 0,
    notifications: [],
    outbox: [],
    chatMessages: [],
    chatRooms: [{ id: 1, booking_id: 10, room_code: `CHAT-${BOOKING_NUMBER}`, is_active: 1, created_at: new Date() }],
    chatParticipants: [],
    nextMessageId: 1,
    nextParticipantId: 1,
    assignmentId: null,
  };
}

function bookingRow(state) {
  const row = {
    id: state.bookingId,
    booking_number: state.bookingNumber,
    status: state.status,
    total_amount: state.totalAmount,
    currency: state.currency,
    customer_name: state.customerName,
    customer_user_id: state.customerUserId,
    driver_id: state.driverUserId ?? 5,
    commission_status: state.commissionStatus,
    commission_amount: state.commissionAmount,
    commission_receipt_file_id: state.commissionReceiptFileId,
    metadata: state.commissionMetadata,
    completed_at: state.status === BOOKING_STATUS.COMPLETED ? '2026-07-01 12:00:00' : null,
    boarding_qr_token_hash: hashToken(state.boardingToken),
    boarding_qr_expires_at: '2099-01-01 00:00:00',
    boarding_qr_used_at: state.boardingQrUsedAt ?? null,
    dropoff_qr_token_hash: state.dropoffToken ? hashToken(state.dropoffToken) : null,
    dropoff_qr_expires_at: state.dropoffToken ? '2099-01-01 00:00:00' : null,
    dropoff_qr_used_at: state.dropoffQrUsedAt ?? null,
    receipt_mime_type: null,
    receipt_file_size: null,
    receipt_original_filename: null,
    receipt_uploaded_at: null,
  };
  if (state.commissionReceiptFileId != null) {
    row.receipt_mime_type = state.receiptMimeType ?? 'application/pdf';
    row.receipt_file_size = state.receiptFileSize ?? 8;
    row.receipt_original_filename = state.receiptOriginalFilename ?? 'transfer-slip.pdf';
    row.receipt_uploaded_at = state.receiptUploadedAt ?? '2026-07-12 12:00:00';
  }
  return row;
}

function buildMvpHarness(initialState = createLifecycleState()) {
  const state = initialState;
  const pool = { async getConnection() { return connStub(state); } };
  const settlementStub = { async driverHasBlockingSettlement() { return false; } };

  const bookingRepo = {
    async findByBookingNumberForUpdate(_c, num) {
      return num === state.bookingNumber ? bookingRow(state) : null;
    },
    async findByBookingNumber(_c, num) {
      return num === state.bookingNumber ? bookingRow(state) : null;
    },
    async findActiveDriverBookingByNumberForUpdate(_c, driverUserId, num) {
      if (num !== state.bookingNumber) return null;
      if (state.activeDriverUserId !== driverUserId) return null;
      return bookingRow(state);
    },
    async findActiveDriverBookingByNumber(driverUserId, num) {
      return this.findActiveDriverBookingByNumberForUpdate(null, driverUserId, num);
    },
    async findActiveGuestTokenForBooking(_c, bookingId, tokenHash) {
      if (bookingId !== state.bookingId || tokenHash !== state.guestTokenHash) return null;
      return { id: 1 };
    },
    async findActiveAssignmentForUpdate() {
      if (!state.activeDriverUserId) return null;
      return { id: state.assignmentId ?? 1, driver_id: state.activeDriverUserId, status: 'ACTIVE' };
    },
    async insertAssignment() {
      state.assignmentId = 1;
      return 1;
    },
    async deactivateAssignment() {},
    async updateCommissionFields(_c, bookingId, fields) {
      state.commissionUpdates += 1;
      if (fields.commissionStatus) state.commissionStatus = fields.commissionStatus;
      if (fields.commissionAmount != null) state.commissionAmount = fields.commissionAmount;
      if (fields.commissionReceiptFileId != null) {
        state.commissionReceiptFileId = fields.commissionReceiptFileId;
      }
      if (fields.metadata) state.commissionMetadata = fields.metadata;
    },
    async insertActivityLog() {},
    async findSettlementByBookingNumberForUpdate(_c, num) {
      return num === state.bookingNumber ? bookingRow(state) : null;
    },
    async findSettlementByBookingNumber(num) {
      return num === state.bookingNumber ? bookingRow(state) : null;
    },
    async driverOwnsSettlementBooking(driverId, num) {
      return driverId === 5 && num === state.bookingNumber;
    },
    async findQrTokenBooking(_c, tokenHash) {
      if (tokenHash === hashToken(state.boardingToken)) {
        return { id: state.bookingId, booking_number: state.bookingNumber, token_type: 'BOARDING' };
      }
      if (state.dropoffToken && tokenHash === hashToken(state.dropoffToken)) {
        return { id: state.bookingId, booking_number: state.bookingNumber, token_type: 'DROPOFF' };
      }
      return null;
    },
    async insertDriverAssignment(_c, assignment) {
      state.assignmentId = 1;
      state.activeDriverUserId = DRIVER_USER_ID;
      state.driverUserId = assignment.driverId;
      return 1;
    },
    async markBoardingQrUsed() {
      state.boardingQrUsedAt = '2026-07-01 11:00:00';
      return true;
    },
    async markDropoffQrUsed() {
      state.dropoffQrUsedAt = '2026-07-01 12:00:00';
      return true;
    },
    async issueDropoffQr(_c, bookingId) {
      state.dropoffToken = 'dropoff-qr-token';
      state.status = BOOKING_STATUS.PICKED_UP;
      return { dropoffQrToken: state.dropoffToken, status: state.status };
    },
  };

  const realStatus = new BookingStatusService(null, null);
  const statusService = {
    validateTransition: realStatus.validateTransition.bind(realStatus),
    async transitionInTransaction(_c, bookingNumber, input) {
      state.status = input.status;
      if (input.status === BOOKING_STATUS.SETTLEMENT_PENDING) {
        state.commissionStatus = COMMISSION_STATUS.DUE;
        state.commissionAmount = 200;
      }
      return {
        result: { bookingNumber, status: input.status, idempotent: false },
        domainEvent: `event.${input.status}`,
        eventPayload: { bookingNumber, status: input.status, bookingId: state.bookingId },
        outboxId: null,
      };
    },
    emitDomainEvent() {},
    async dispatchOutboxAfterCommit() {},
  };

  const driverRepo = {
    async findByUserId(userId) {
      if (userId === DRIVER_USER_ID) return { id: 5, name: 'Driver A', user_id: DRIVER_USER_ID };
      if (userId === OLD_DRIVER_USER_ID) return { id: 6, name: 'Old Driver', user_id: OLD_DRIVER_USER_ID };
      return null;
    },
    async findByIdForUpdate(_c, id) {
      if (id === 5) return { id: 5, name: 'Driver A', user_id: DRIVER_USER_ID, is_active: 1, status: 'ACTIVE' };
      return null;
    },
    async findPrimaryVehicle() {
      return { id: 1 };
    },
    async hasActiveJob(_c, driverId) {
      return driverId === 5
        && state.activeDriverUserId === DRIVER_USER_ID
        && [
          BOOKING_STATUS.DRIVER_ASSIGNED,
          BOOKING_STATUS.ON_ROUTE,
          BOOKING_STATUS.DRIVER_ARRIVED,
          BOOKING_STATUS.PICKED_UP,
          BOOKING_STATUS.SETTLEMENT_PENDING,
        ].includes(state.status);
    },
  };

  const fileRepository = {
    async insert(_c, data) {
      state.storedReceiptPath = data.filePath;
      state.receiptMimeType = data.mimeType;
      state.receiptFileSize = data.fileSize;
      state.receiptOriginalFilename = data.originalFilename;
      return 77;
    },
    async softDelete() {},
  };

  const bookingService = {
    validateBookingNumber: (n) => String(n).trim().toUpperCase(),
    async assertCustomerOrGuestAccess(_conn, booking, authUser, guestAccessToken) {
      if (authUser?.role === 'CUSTOMER' && booking.customer_user_id === authUser.id) return;
      const token = String(guestAccessToken ?? '').trim();
      if (!token || hashToken(token) !== state.guestTokenHash) {
        const err = new Error('denied');
        err.errorCode = ERROR_CODES.BOOKING_NOT_ACCESSIBLE;
        throw err;
      }
    },
  };

  const chatRepository = {
    async findRoomByBookingIdForUpdate(_c, bookingId) {
      return state.chatRooms.find((r) => r.booking_id === bookingId) ?? null;
    },
    async findRoomByBookingId(_c, bookingId) {
      return state.chatRooms.find((r) => r.booking_id === bookingId) ?? null;
    },
    async listParticipants(_c, roomId) {
      return state.chatParticipants.filter((p) => p.chat_room_id === roomId);
    },
    async findParticipant(_c, roomId, role, userId) {
      return state.chatParticipants.find((p) =>
        p.chat_room_id === roomId && p.participant_role === role && p.user_id === userId) ?? null;
    },
    async findGuestParticipant(_c, roomId) {
      return state.chatParticipants.find((p) =>
        p.chat_room_id === roomId && p.participant_role === 'CUSTOMER' && p.user_id == null) ?? null;
    },
    async insertParticipant(_c, roomId, participant) {
      const row = {
        id: state.nextParticipantId++,
        chat_room_id: roomId,
        user_id: participant.userId ?? null,
        participant_role: participant.participantRole,
        display_name: participant.displayName,
        last_read_at: null,
      };
      state.chatParticipants.push(row);
      return row.id;
    },
    async findParticipantById(_c, id) {
      return state.chatParticipants.find((p) => p.id === id) ?? null;
    },
    async findMessageByClientId(_c, roomId, participantId, clientMessageId) {
      return state.chatMessages.find((m) =>
        m.chat_room_id === roomId
        && m.sender_participant_id === participantId
        && m.client_message_id === clientMessageId) ?? null;
    },
    async insertMessage(_c, message) {
      const row = {
        id: state.nextMessageId++,
        chat_room_id: message.chatRoomId,
        sender_user_id: message.senderUserId,
        sender_participant_id: message.senderParticipantId,
        sender_role: message.senderRole,
        sender_name: message.senderName,
        content: message.content,
        client_message_id: message.clientMessageId,
        created_at: new Date(),
      };
      state.chatMessages.push(row);
      return row.id;
    },
    async findMessageById(_c, id, roomId) {
      return state.chatMessages.find((m) => m.id === id && m.chat_room_id === roomId) ?? null;
    },
    async listMessages(_c, roomId) {
      return state.chatMessages.filter((m) => m.chat_room_id === roomId);
    },
    async findLastMessage(_c, roomId) {
      const items = state.chatMessages.filter((m) => m.chat_room_id === roomId);
      return items.length ? items[items.length - 1] : null;
    },
    async countUnreadForParticipant() { return 0; },
    async updateParticipantLastRead() {},
    async insertMessageRead() {},
    async listAdminChatSummaries() { return []; },
    async countAdminChatSummaries() { return 0; },
  };

  const outboxRepository = {
    async insertNotificationEvent(_c, row) {
      state.outbox.push(row);
      return state.outbox.length;
    },
  };

  const reviewRepository = {
    async findByBookingId() {
      return state.reviewId
        ? { id: state.reviewId, rating: 5, comment: 'Great trip', moderation_status: 'VISIBLE' }
        : null;
    },
    async findByBookingIdForUpdate() {
      return state.reviewId ? { id: state.reviewId } : null;
    },
    async insert(_conn, _data) {
      state.reviewId = 1;
      state.reviewCount += 1;
      return 1;
    },
    async getVisibleRatingSummaryForDriver() {
      return state.reviewId ? { averageRating: 5, reviewCount: 1 } : { averageRating: null, reviewCount: 0 };
    },
  };

  const settingsRepo = {
    async findByGroupAndKey(_g, key) {
      if (key === 'commission_rate_percent') return { value: '10' };
      if (key === 'commission_due_days') return { value: '7' };
      return null;
    },
  };

  const adminDispatch = new AdminDispatchService(
    pool,
    bookingRepo,
    driverRepo,
    statusService,
    settlementStub,
    null,
    null,
    new (require('../src/services/driverCandidateScoring.service'))(),
  );
  const driverJobService = new DriverJobService(bookingRepo);
  const driverTripFlow = new DriverTripFlowService(pool, bookingRepo, statusService, driverJobService);
  const driverQr = new DriverQrService(pool, bookingRepo, statusService, driverJobService);
  const commission = new CommissionSettlementService(
    pool,
    bookingRepo,
    driverRepo,
    fileRepository,
    settingsRepo,
    outboxRepository,
    null,
    statusService,
  );
  const review = new ReviewService(
    pool,
    bookingRepo,
    reviewRepository,
    driverRepo,
    bookingService,
    outboxRepository,
    null,
  );
  const chat = new ChatService(pool, chatRepository, bookingRepo, driverRepo, {}, outboxRepository, null);

  return {
    state,
    adminDispatch,
    driverTripFlow,
    driverQr,
    commission,
    review,
    chat,
    bookingRepo,
    driverRepo,
  };
}

test('MVP lifecycle — booking through review with commission, notifications, and chat', async () => {
  const h = buildMvpHarness();
  const { state } = h;

  state.status = BOOKING_STATUS.CONFIRMED;
  await h.adminDispatch.assignDriver(
    BOOKING_NUMBER,
    { driverId: 5 },
    ADMIN_USER,
  );
  assert.equal(state.status, BOOKING_STATUS.DRIVER_ASSIGNED);
  assert.equal(state.activeDriverUserId, DRIVER_USER_ID);

  await h.driverTripFlow.startOnRoute(DRIVER_USER_ID, BOOKING_NUMBER);
  assert.equal(state.status, BOOKING_STATUS.ON_ROUTE);

  await h.driverTripFlow.markArrived(DRIVER_USER_ID, BOOKING_NUMBER);
  assert.equal(state.status, BOOKING_STATUS.DRIVER_ARRIVED);

  await assert.rejects(
    () => h.chat.getRoom(BOOKING_NUMBER, null, GUEST_TOKEN),
    (err) =>
      err.errorCode === ERROR_CODES.CHAT_NOT_ACCESSIBLE &&
      err.statusCode === 410,
  );

  await assert.rejects(
    () =>
      h.chat.sendMessage(BOOKING_NUMBER, null, GUEST_TOKEN, {
        text: 'Thanks driver',
        clientMessageId: 'mvp-chat-msg-1',
      }),
    (err) =>
      err.errorCode === ERROR_CODES.CHAT_NOT_ACCESSIBLE &&
      err.statusCode === 410,
  );
  assert.equal(state.chatMessages.length, 0);

  await h.driverQr.scanBoarding(
    DRIVER_USER_ID,
    BOOKING_NUMBER,
    state.boardingToken,
  );
  assert.equal(state.status, BOOKING_STATUS.PICKED_UP);

  await h.driverQr.scanDropoff(
    DRIVER_USER_ID,
    BOOKING_NUMBER,
    state.dropoffToken,
  );
  assert.equal(state.status, BOOKING_STATUS.SETTLEMENT_PENDING);
  assert.equal(state.commissionStatus, COMMISSION_STATUS.DUE);
  assert.equal(state.commissionAmount, 200);

  await assert.rejects(
    () => h.commission.approve(BOOKING_NUMBER, ADMIN_USER),
    (err) => err.errorCode === ERROR_CODES.RECEIPT_REQUIRED,
  );
  await assert.rejects(
    () => h.adminDispatch.ensureDriverEligible(connStub(state), 5),
    (err) => err.errorCode === ERROR_CODES.DRIVER_NOT_ELIGIBLE,
  );

  const uploadPath = path.join(uploadDir, 'mvp-transfer-slip.pdf');
  fs.writeFileSync(uploadPath, '%PDF-1.4');
  await h.commission.uploadReceipt(DRIVER_USER_ID, BOOKING_NUMBER, {
    path: uploadPath,
    mimetype: 'application/pdf',
    size: 8,
    originalname: 'transfer-slip.pdf',
  });
  assert.equal(state.commissionReceiptFileId, 77);

  await h.commission.approve(BOOKING_NUMBER, ADMIN_USER);
  assert.equal(state.status, BOOKING_STATUS.COMPLETED);
  assert.equal(state.commissionStatus, COMMISSION_STATUS.PAID);

  await h.commission.approve(BOOKING_NUMBER, ADMIN_USER);
  assert.equal(state.status, BOOKING_STATUS.COMPLETED);
  const eligibleDriver = await h.adminDispatch.ensureDriverEligible(
    connStub(state),
    5,
  );
  assert.equal(eligibleDriver.id, 5);

  if (state.storedReceiptPath) {
    const storedReceipt = path.join(uploadDir, state.storedReceiptPath);
    if (fs.existsSync(storedReceipt)) fs.unlinkSync(storedReceipt);
  }

  const reviewResult = await h.review.submitBookingReview(
    BOOKING_NUMBER,
    { rating: 5, comment: 'Great trip', guestAccessToken: GUEST_TOKEN },
    null,
  );
  assert.equal(reviewResult.submitted, true);
  assert.equal(state.reviewCount, 1);

  await assert.rejects(
    () => h.review.submitBookingReview(
      BOOKING_NUMBER,
      { rating: 4, comment: 'again', guestAccessToken: GUEST_TOKEN },
      null,
    ),
    (err) => err.errorCode === ERROR_CODES.REVIEW_ALREADY_SUBMITTED,
  );

  const summary = await h.review.getDriverRatingSummary(DRIVER_USER_ID);
  assert.equal(summary.reviewCount, 1);

  await assert.rejects(
    () => h.chat.getRoom(BOOKING_NUMBER, null, GUEST_TOKEN),
    (err) =>
      err.errorCode === ERROR_CODES.CHAT_NOT_ACCESSIBLE &&
      err.statusCode === 410,
  );
});

test('MVP failure paths — wrong driver, guest, reassignment, notification isolation', async () => {
  const h = buildMvpHarness();
  h.state.status = BOOKING_STATUS.DRIVER_ASSIGNED;
  h.state.activeDriverUserId = DRIVER_USER_ID;

  await assert.rejects(
    () => h.driverTripFlow.markArrived(OLD_DRIVER_USER_ID, BOOKING_NUMBER),
    (err) => err.errorCode === ERROR_CODES.BOOKING_NOT_FOUND || err.statusCode === 404,
  );

  await assert.rejects(
    () => h.review.submitBookingReview(
      BOOKING_NUMBER,
      { rating: 5, guestAccessToken: 'wrong-guest-token' },
      null,
    ),
    (err) => err.errorCode === ERROR_CODES.BOOKING_NOT_ACCESSIBLE,
  );

  h.state.activeDriverUserId = DRIVER_USER_ID;
  await assert.rejects(
    () =>
      h.chat.getRoom(
        BOOKING_NUMBER,
        { id: DRIVER_USER_ID, role: 'DRIVER' },
        null,
      ),
    (err) =>
      err.errorCode === ERROR_CODES.CHAT_NOT_ACCESSIBLE &&
      err.statusCode === 410,
  );

  h.state.activeDriverUserId = OLD_DRIVER_USER_ID;
  await assert.rejects(
    () => h.chat.sendMessage(BOOKING_NUMBER, { id: DRIVER_USER_ID, role: 'DRIVER' }, null, {
      text: 'blocked',
      clientMessageId: 'mvp-driver-blocked',
    }),
    (err) => err.errorCode === ERROR_CODES.CHAT_NOT_ACCESSIBLE,
  );
});

test('MVP HTTP boundaries — guest header required for review lookup', async () => {
  const AppError = require('../src/utils/AppError');
  const HTTP_STATUS = require('../src/constants/httpStatus');

  container.register('reviewService', () => ({
    async getBookingReview(_bookingNumber, authUser, guestAccessToken) {
      if (!authUser && !String(guestAccessToken ?? '').trim()) {
        throw new AppError('Booking is not accessible', {
          statusCode: HTTP_STATUS.FORBIDDEN,
          errorCode: ERROR_CODES.BOOKING_NOT_ACCESSIBLE,
        });
      }
      return { eligible: true, submitted: false };
    },
  }));

  const noHeader = await request(app).get(`/api/v1/bookings/${BOOKING_NUMBER}/review`);
  assert.equal(noHeader.status, 403);

  const withHeader = await request(app)
    .get(`/api/v1/bookings/${BOOKING_NUMBER}/review`)
    .set('X-Guest-Access-Token', GUEST_TOKEN);
  assert.equal(withHeader.status, 200);

  const queryLeak = await request(app)
    .get(`/api/v1/bookings/${BOOKING_NUMBER}/review?guestAccessToken=leak`);
  assert.notEqual(queryLeak.status, 200);
});

test('legacy /api/v1/chat routes return deprecation 404', async () => {
  const res = await request(app).get('/api/v1/chat/rooms');
  assert.equal(res.status, 404);
  assert.match(res.body.message, /deprecated/i);
});

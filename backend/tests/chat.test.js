process.env.NODE_ENV = "test";
process.env.DB_USER = process.env.DB_USER || "test";
process.env.DB_NAME = process.env.DB_NAME || "ttaxi_test";
process.env.JWT_ACCESS_SECRET =
  process.env.JWT_ACCESS_SECRET || "test-access-secret-value";
process.env.JWT_REFRESH_SECRET =
  process.env.JWT_REFRESH_SECRET || "test-refresh-secret-value";

const { test } = require("node:test");
const assert = require("node:assert/strict");
const ChatService = require("../src/services/chat.service");
const AppError = require("../src/utils/AppError");
const ERROR_CODES = require("../src/constants/errorCodes");
const ROLES = require("../src/constants/roles");
const BOOKING_STATUS = require("../src/constants/reservationStatus");

function booking(overrides = {}) {
  return {
    id: 10,
    booking_number: "TX202607010001",
    status: BOOKING_STATUS.DRIVER_ASSIGNED,
    customer_name: "Kim",
    customer_user_id: 8,
    driver_id: 9,
    ...overrides,
  };
}

function buildHarness(overrides = {}) {
  const state = {
    rooms: [],
    participants: [],
    messages: [],
    outbox: [],
    nextRoomId: 1,
    nextParticipantId: 1,
    nextMessageId: 1,
    guestValid: overrides.guestValid !== false,
    driverActive: overrides.driverActive !== false,
  };

  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };

  const pool = {
    async getConnection() {
      return conn;
    },
  };

  const chatRepository = {
    async findRoomByBookingIdForUpdate(_c, bookingId) {
      return state.rooms.find((r) => r.booking_id === bookingId) ?? null;
    },
    async findRoomByBookingId(_c, bookingId) {
      return state.rooms.find((r) => r.booking_id === bookingId) ?? null;
    },
    async insertRoom(_c, bookingId, roomCode) {
      if (state.rooms.some((r) => r.booking_id === bookingId)) {
        const err = new Error("dup");
        err.code = "ER_DUP_ENTRY";
        throw err;
      }
      const row = {
        id: state.nextRoomId++,
        booking_id: bookingId,
        room_code: roomCode,
        is_active: 1,
        created_at: new Date(),
      };
      state.rooms.push(row);
      return row.id;
    },
    async findParticipant(_c, roomId, role, userId) {
      return (
        state.participants.find(
          (p) =>
            p.chat_room_id === roomId &&
            p.participant_role === role &&
            (userId == null ? p.user_id == null : p.user_id === userId),
        ) ?? null
      );
    },
    async findGuestParticipant(_c, roomId) {
      return (
        state.participants.find(
          (p) =>
            p.chat_room_id === roomId &&
            p.participant_role === "CUSTOMER" &&
            p.user_id == null,
        ) ?? null
      );
    },
    async findParticipantById(_c, id) {
      return state.participants.find((p) => p.id === id) ?? null;
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
      state.participants.push(row);
      return row.id;
    },
    async deactivateParticipant(_c, roomId, role, userId) {
      const before = state.participants.length;
      state.participants = state.participants.filter(
        (p) =>
          !(
            p.chat_room_id === roomId &&
            p.participant_role === role &&
            p.user_id === userId
          ),
      );
      return before - state.participants.length;
    },
    async reactivateParticipant() {
      return 0;
    },
    async listParticipants(_c, roomId) {
      return state.participants.filter((p) => p.chat_room_id === roomId);
    },
    async findMessageByClientId(_c, roomId, participantId, clientMessageId) {
      return (
        state.messages.find(
          (m) =>
            m.chat_room_id === roomId &&
            m.sender_participant_id === participantId &&
            m.client_message_id === clientMessageId,
        ) ?? null
      );
    },
    async insertMessage(_c, message) {
      const row = {
        id: state.nextMessageId++,
        chat_room_id: message.chatRoomId,
        sender_user_id: message.senderUserId ?? null,
        sender_participant_id: message.senderParticipantId,
        sender_role: message.senderRole,
        sender_name: message.senderName,
        content: message.content,
        client_message_id: message.clientMessageId,
        created_at: new Date(),
      };
      state.messages.push(row);
      return row.id;
    },
    async findMessageById(_c, messageId, roomId = null) {
      return (
        state.messages.find(
          (m) =>
            m.id === messageId && (roomId == null || m.chat_room_id === roomId),
        ) ?? null
      );
    },
    async listMessages(_c, roomId) {
      return [...state.messages]
        .filter((m) => m.chat_room_id === roomId)
        .sort((a, b) => b.id - a.id);
    },
    async countUnreadForParticipant(_c, roomId, participant) {
      return state.messages.filter(
        (m) =>
          m.chat_room_id === roomId &&
          m.sender_participant_id !== participant.id &&
          (!participant.last_read_at ||
            m.created_at > participant.last_read_at),
      ).length;
    },
    async updateParticipantLastRead(_c, participantId, readAt) {
      const p = state.participants.find((item) => item.id === participantId);
      if (p) p.last_read_at = readAt;
    },
    async insertMessageRead() {},
    async findLastMessage(_c, roomId) {
      const rows = state.messages.filter((m) => m.chat_room_id === roomId);
      return rows.length ? rows[rows.length - 1] : null;
    },
    async listAdminChatSummaries() {
      return [];
    },
    async countAdminChatSummaries() {
      return 0;
    },
    ...overrides.chatRepository,
  };

  const bookingRepository = {
    async findByBookingNumberForUpdate(_c, bookingNumber) {
      if (bookingNumber !== "TX202607010001") return null;
      return booking(overrides.booking);
    },
    async findActiveGuestTokenForBooking() {
      return state.guestValid ? { id: 1 } : null;
    },
    async findActiveDriverBookingByNumberForUpdate(
      _c,
      driverUserId,
      bookingNumber,
    ) {
      if (!state.driverActive || bookingNumber !== "TX202607010001")
        return null;
      return { driver_user_id: driverUserId };
    },
    async findActiveAssignmentForUpdate() {
      return overrides.driverAssigned === false
        ? null
        : { id: 1, driver_id: 9 };
    },
    ...overrides.bookingRepository,
  };

  const outboxRepository = {
    async insertNotificationEvent(_c, data) {
      state.outbox.push(data);
      return state.outbox.length;
    },
  };

  const outboxProcessor = {
    async dispatchOutboxIds() {},
  };

  const service = new ChatService(
    pool,
    chatRepository,
    bookingRepository,
    {
      async findByUserId() {
        return { name: "Driver A" };
      },
    },
    {
      async findById() {
        return { name: "Admin" };
      },
    },
    outboxRepository,
    outboxProcessor,
  );

  return { service, state, conn };
}

test("one room per booking via ensureRoom idempotency", async () => {
  const { service, state } = buildHarness();
  state.rooms.push({
    id: 1,
    booking_id: 10,
    room_code: "CHAT-TX202607010001",
    is_active: 1,
    created_at: new Date(),
  });
  state.participants.push({
    id: 1,
    chat_room_id: 1,
    user_id: 8,
    participant_role: "CUSTOMER",
    display_name: "Kim",
    last_read_at: null,
  });
  const room = await service.getRoom(
    "TX202607010001",
    { id: 8, role: ROLES.CUSTOMER },
    null,
  );
  assert.equal(room.roomId, 1);
  assert.equal(state.rooms.length, 1);
});

test("assignment sync creates driver and admin participants and removes old driver", async () => {
  const { service, state, conn } = buildHarness();
  state.rooms.push({
    id: 1,
    booking_id: 10,
    room_code: "CHAT-TX202607010001",
    is_active: 1,
    created_at: new Date(),
  });
  state.participants.push(
    {
      id: 1,
      chat_room_id: 1,
      user_id: null,
      participant_role: "CUSTOMER",
      display_name: "Kim",
      last_read_at: null,
    },
    {
      id: 2,
      chat_room_id: 1,
      user_id: 90,
      participant_role: "DRIVER",
      display_name: "Old Driver",
      last_read_at: null,
    },
  );

  await service.syncAssignedParticipants(conn, {
    booking: booking(),
    driver: { id: 9, user_id: 99, name: "Driver A" },
    adminUser: { id: 1, role: ROLES.ADMIN, email: "admin@example.com" },
    previousDriverUserId: 90,
  });

  assert.deepEqual(
    state.participants.map((item) => [item.participant_role, item.user_id]),
    [
      ["CUSTOMER", null],
      ["DRIVER", 99],
      ["ADMIN", 1],
    ],
  );
});

test("valid customer access", async () => {
  const { service, state } = buildHarness();
  state.rooms.push({
    id: 1,
    booking_id: 10,
    room_code: "CHAT-TX202607010001",
    is_active: 1,
    created_at: new Date(),
  });
  state.participants.push({
    id: 1,
    chat_room_id: 1,
    user_id: 8,
    participant_role: "CUSTOMER",
    display_name: "Kim",
    last_read_at: null,
  });
  const room = await service.getRoom(
    "TX202607010001",
    { id: 8, role: ROLES.CUSTOMER },
    null,
  );
  assert.equal(room.bookingNumber, "TX202607010001");
  assert.equal(room.sendingAllowed, true);
});

test("valid guest header access", async () => {
  const { service, state } = buildHarness();
  state.rooms.push({
    id: 1,
    booking_id: 10,
    room_code: "CHAT-TX202607010001",
    is_active: 1,
    created_at: new Date(),
  });
  const room = await service.getRoom("TX202607010001", null, "guest-token");
  assert.equal(room.bookingNumber, "TX202607010001");
  assert.ok(state.participants.some((p) => p.user_id == null));
});

test("booking number alone rejected", async () => {
  const { service } = buildHarness();
  await assert.rejects(
    () => service.getRoom("TX202607010001", null, null),
    (err) => err.errorCode === ERROR_CODES.CHAT_NOT_ACCESSIBLE,
  );
});

test("wrong guest token rejected", async () => {
  const { service, state } = buildHarness({ guestValid: false });
  state.rooms.push({
    id: 1,
    booking_id: 10,
    room_code: "CHAT-TX202607010001",
    is_active: 1,
    created_at: new Date(),
  });
  await assert.rejects(
    () => service.getRoom("TX202607010001", null, "bad-token"),
    (err) => err.errorCode === ERROR_CODES.CHAT_NOT_ACCESSIBLE,
  );
});

test("assigned driver access", async () => {
  const { service, state } = buildHarness();
  state.rooms.push({
    id: 1,
    booking_id: 10,
    room_code: "CHAT-TX202607010001",
    is_active: 1,
    created_at: new Date(),
  });
  const room = await service.getRoom(
    "TX202607010001",
    { id: 44, role: ROLES.DRIVER },
    null,
  );
  assert.equal(room.sendingAllowed, true);
  assert.ok(state.participants.some((p) => p.participant_role === "DRIVER"));
});

test("old reassigned driver cannot send", async () => {
  const { service, state } = buildHarness({ driverActive: false });
  state.rooms.push({
    id: 1,
    booking_id: 10,
    room_code: "CHAT-TX202607010001",
    is_active: 1,
    created_at: new Date(),
  });
  await assert.rejects(
    () =>
      service.sendMessage(
        "TX202607010001",
        { id: 44, role: ROLES.DRIVER },
        null,
        {
          text: "hello",
          clientMessageId: "11111111-1111-4111-8111-111111111111",
        },
      ),
    (err) => err.errorCode === ERROR_CODES.CHAT_NOT_ACCESSIBLE,
  );
});

test("admin access", async () => {
  const { service, state } = buildHarness();
  state.rooms.push({
    id: 1,
    booking_id: 10,
    room_code: "CHAT-TX202607010001",
    is_active: 1,
    created_at: new Date(),
  });
  const room = await service.getRoom(
    "TX202607010001",
    { id: 1, role: ROLES.ADMIN },
    null,
  );
  assert.equal(room.bookingNumber, "TX202607010001");
  assert.ok(state.participants.some((p) => p.participant_role === "ADMIN"));
});

test("message trim and validation", async () => {
  const { service } = buildHarness();
  await assert.rejects(
    () =>
      service.sendMessage(
        "TX202607010001",
        { id: 8, role: ROLES.CUSTOMER },
        null,
        {
          text: "   ",
          clientMessageId: "11111111-1111-4111-8111-111111111111",
        },
      ),
    (err) => err.errorCode === ERROR_CODES.CHAT_MESSAGE_EMPTY,
  );
});

test("message length limit", async () => {
  const { service } = buildHarness();
  await assert.rejects(
    () =>
      service.sendMessage(
        "TX202607010001",
        { id: 8, role: ROLES.CUSTOMER },
        null,
        {
          text: "x".repeat(2001),
          clientMessageId: "11111111-1111-4111-8111-111111111111",
        },
      ),
    (err) => err.errorCode === ERROR_CODES.CHAT_MESSAGE_TOO_LONG,
  );
});

test("duplicate clientMessageId returns one message", async () => {
  const { service, state } = buildHarness();
  state.rooms.push({
    id: 1,
    booking_id: 10,
    room_code: "CHAT-TX202607010001",
    is_active: 1,
    created_at: new Date(),
  });
  state.participants.push({
    id: 1,
    chat_room_id: 1,
    user_id: 8,
    participant_role: "CUSTOMER",
    display_name: "Kim",
    last_read_at: null,
  });
  state.participants.push({
    id: 2,
    chat_room_id: 1,
    user_id: 44,
    participant_role: "DRIVER",
    display_name: "Driver",
    last_read_at: null,
  });
  const payload = {
    text: "Hello",
    clientMessageId: "22222222-2222-4222-8222-222222222222",
  };
  await service.sendMessage(
    "TX202607010001",
    { id: 8, role: ROLES.CUSTOMER },
    null,
    payload,
  );
  await service.sendMessage(
    "TX202607010001",
    { id: 8, role: ROLES.CUSTOMER },
    null,
    payload,
  );
  assert.equal(state.messages.length, 1);
});

test("guest pickup alert stores fixed text once", async () => {
  const { service, state } = buildHarness({
    booking: { customer_user_id: null },
  });
  const first = await service.sendPickupAlert(
    "TX202607010001",
    null,
    "guest-token",
  );
  const second = await service.sendPickupAlert(
    "TX202607010001",
    null,
    "guest-token",
  );

  assert.equal(first.text, "도착하고 수화물을 찾았습니다");
  assert.equal(first.alreadySent, false);
  assert.equal(second.alreadySent, true);
  assert.equal(state.messages.length, 1);
});

test("pickup alert rejects missing assignment and terminal status", async () => {
  const missingAssignment = buildHarness({
    booking: { customer_user_id: null },
    driverAssigned: false,
  });
  await assert.rejects(
    () =>
      missingAssignment.service.sendPickupAlert(
        "TX202607010001",
        null,
        "guest-token",
      ),
    (err) => err.errorCode === ERROR_CODES.NO_ACTIVE_ASSIGNMENT,
  );

  const completed = buildHarness({
    booking: {
      customer_user_id: null,
      status: BOOKING_STATUS.COMPLETED,
    },
  });
  await assert.rejects(
    () =>
      completed.service.sendPickupAlert("TX202607010001", null, "guest-token"),
    (err) => err.errorCode === ERROR_CODES.INVALID_STATUS_TRANSITION,
  );
});

test("pickup alert rejects invalid guest token", async () => {
  const { service } = buildHarness({
    booking: { customer_user_id: null },
    guestValid: false,
  });
  await assert.rejects(
    () => service.sendPickupAlert("TX202607010001", null, "wrong-token"),
    (err) => err.errorCode === ERROR_CODES.CHAT_NOT_ACCESSIBLE,
  );
});

test("terminal booking read-only rule", async () => {
  const { service, state } = buildHarness({
    booking: booking({ status: BOOKING_STATUS.COMPLETED }),
  });
  state.rooms.push({
    id: 1,
    booking_id: 10,
    room_code: "CHAT-TX202607010001",
    is_active: 1,
    created_at: new Date(),
  });
  state.participants.push({
    id: 1,
    chat_room_id: 1,
    user_id: 8,
    participant_role: "CUSTOMER",
    display_name: "Kim",
    last_read_at: null,
  });
  const room = await service.getRoom(
    "TX202607010001",
    { id: 8, role: ROLES.CUSTOMER },
    null,
  );
  assert.equal(room.sendingAllowed, false);
  await assert.rejects(
    () =>
      service.sendMessage(
        "TX202607010001",
        { id: 8, role: ROLES.CUSTOMER },
        null,
        {
          text: "late message",
          clientMessageId: "33333333-3333-4333-8333-333333333333",
        },
      ),
    (err) => err.errorCode === ERROR_CODES.CHAT_READ_ONLY,
  );
});

test("chat notification outbox created once per recipient", async () => {
  const { service, state } = buildHarness();
  state.rooms.push({
    id: 1,
    booking_id: 10,
    room_code: "CHAT-TX202607010001",
    is_active: 1,
    created_at: new Date(),
  });
  state.participants.push({
    id: 1,
    chat_room_id: 1,
    user_id: 8,
    participant_role: "CUSTOMER",
    display_name: "Kim",
    last_read_at: null,
  });
  state.participants.push({
    id: 2,
    chat_room_id: 1,
    user_id: 44,
    participant_role: "DRIVER",
    display_name: "Driver",
    last_read_at: null,
  });
  await service.sendMessage(
    "TX202607010001",
    { id: 8, role: ROLES.CUSTOMER },
    null,
    {
      text: "Ping driver",
      clientMessageId: "44444444-4444-4444-8444-444444444444",
    },
  );
  assert.equal(state.outbox.length, 1);
  assert.equal(state.outbox[0].eventType, "chat.message_sent");
  assert.equal(state.outbox[0].payload.messageId, 1);
});

test("unread excludes own messages", async () => {
  const { service, state } = buildHarness();
  state.rooms.push({
    id: 1,
    booking_id: 10,
    room_code: "CHAT-TX202607010001",
    is_active: 1,
    created_at: new Date(),
  });
  state.participants.push({
    id: 1,
    chat_room_id: 1,
    user_id: 8,
    participant_role: "CUSTOMER",
    display_name: "Kim",
    last_read_at: null,
  });
  state.participants.push({
    id: 2,
    chat_room_id: 1,
    user_id: 44,
    participant_role: "DRIVER",
    display_name: "Driver",
    last_read_at: null,
  });
  await service.sendMessage(
    "TX202607010001",
    { id: 8, role: ROLES.CUSTOMER },
    null,
    {
      text: "mine",
      clientMessageId: "55555555-5555-4555-8555-555555555555",
    },
  );
  const room = await service.getRoom(
    "TX202607010001",
    { id: 8, role: ROLES.CUSTOMER },
    null,
  );
  assert.equal(room.unreadCount, 0);
  const driverRoom = await service.getRoom(
    "TX202607010001",
    { id: 44, role: ROLES.DRIVER },
    null,
  );
  assert.equal(driverRoom.unreadCount, 1);
});

test("read state decreases unread count", async () => {
  const { service, state } = buildHarness();
  state.rooms.push({
    id: 1,
    booking_id: 10,
    room_code: "CHAT-TX202607010001",
    is_active: 1,
    created_at: new Date(),
  });
  state.participants.push({
    id: 1,
    chat_room_id: 1,
    user_id: 8,
    participant_role: "CUSTOMER",
    display_name: "Kim",
    last_read_at: null,
  });
  state.participants.push({
    id: 2,
    chat_room_id: 1,
    user_id: 44,
    participant_role: "DRIVER",
    display_name: "Driver",
    last_read_at: null,
  });
  const sent = await service.sendMessage(
    "TX202607010001",
    { id: 8, role: ROLES.CUSTOMER },
    null,
    {
      text: "hello driver",
      clientMessageId: "66666666-6666-4666-8666-666666666666",
    },
  );
  const read = await service.markRead(
    "TX202607010001",
    { id: 44, role: ROLES.DRIVER },
    null,
    {
      upToMessageId: sent.message.messageId,
    },
  );
  assert.equal(read.unreadCount, 0);
});

process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  registerChatHandlers,
  socketRoomName,
  evictUnauthorizedDriverSockets,
} = require('../src/socket/handlers/chat.handler');
const ERROR_CODES = require('../src/constants/errorCodes');
const ROLES = require('../src/constants/roles');

function buildSocket(overrides = {}) {
  const joinedRooms = new Set();
  return {
    id: overrides.id ?? 's1',
    data: {
      authUser: overrides.authUser ?? { id: 8, role: 'CUSTOMER' },
      guestAccessToken: overrides.guestAccessToken ?? null,
      activeChatRoomId: overrides.activeChatRoomId ?? null,
      activeBookingNumber: overrides.activeBookingNumber ?? null,
    },
    joinedRooms,
    emitted: [],
    async join(roomKey) {
      this.joinedRooms.add(roomKey);
    },
    async leave(roomKey) {
      this.joinedRooms.delete(roomKey);
    },
    emit(event, payload) {
      this.emitted.push({ event, payload });
    },
    handlers: {},
    on(event, handler) {
      this.handlers[event] = handler;
    },
  };
}

function buildIo(roomSockets = {}) {
  const emitted = [];
  return {
    emitted,
    to(roomKey) {
      return {
        emit(event, payload) {
          emitted.push({ roomKey, event, payload });
        },
      };
    },
    in(roomKey) {
      return {
        async fetchSockets() {
          return roomSockets[roomKey] ?? [];
        },
      };
    },
  };
}

test('socket room name is internal chat prefix', () => {
  assert.equal(socketRoomName(42), 'chat:42');
});

test('chat:send persists before broadcast via service order', async () => {
  const order = [];
  const io = buildIo();
  const socket = buildSocket();
  const chatService = {
    async sendMessage() {
      order.push('persist');
      return {
        message: { messageId: 1, text: 'hello' },
        roomId: 9,
        broadcast: true,
      };
    },
    async isDriverAuthorizedForBooking() {
      return true;
    },
  };

  const originalGet = require('../src/helpers/container').get;
  require('../src/helpers/container').get = (name) => {
    if (name === 'chatService') return chatService;
    return originalGet(name);
  };

  registerChatHandlers(io, socket);
  await socket.handlers['chat:send']({
    bookingNumber: 'TX202607010001',
    text: 'hello',
    clientMessageId: '88888888-8888-4888-8888-888888888888',
  });

  require('../src/helpers/container').get = originalGet;
  assert.deepEqual(order, ['persist']);
  assert.equal(io.emitted.length, 1);
  assert.equal(io.emitted[0].event, 'chat:message');
});

test('chat:send persistence failure causes no broadcast', async () => {
  const io = buildIo();
  const socket = buildSocket();
  const chatService = {
    async sendMessage() {
      const err = new Error('db failed');
      err.errorCode = ERROR_CODES.INTERNAL_SERVER_ERROR;
      throw err;
    },
  };

  const originalGet = require('../src/helpers/container').get;
  require('../src/helpers/container').get = (name) => {
    if (name === 'chatService') return chatService;
    return originalGet(name);
  };

  registerChatHandlers(io, socket);
  await socket.handlers['chat:send']({
    bookingNumber: 'TX202607010001',
    text: 'hello',
    clientMessageId: '88888888-8888-4888-8888-888888888888',
  });

  require('../src/helpers/container').get = originalGet;
  assert.equal(io.emitted.length, 0);
  assert.equal(socket.emitted[0].event, 'chat:error');
});

test('duplicate clientMessageId is not rebroadcast', async () => {
  const io = buildIo();
  const socket = buildSocket();
  const chatService = {
    async sendMessage() {
      return {
        message: { messageId: 1, text: 'hello' },
        roomId: 9,
        broadcast: false,
      };
    },
  };

  const originalGet = require('../src/helpers/container').get;
  require('../src/helpers/container').get = (name) => {
    if (name === 'chatService') return chatService;
    return originalGet(name);
  };

  registerChatHandlers(io, socket);
  await socket.handlers['chat:send']({
    bookingNumber: 'TX202607010001',
    text: 'hello',
    clientMessageId: '88888888-8888-4888-8888-888888888888',
  });

  require('../src/helpers/container').get = originalGet;
  assert.equal(io.emitted.length, 0);
});

test('chat:send ignores client sender identity fields', async () => {
  const io = buildIo();
  const socket = buildSocket();
  const chatService = {
    async sendMessage(_bookingNumber, authUser, _guestToken, input) {
      assert.equal(authUser.id, 8);
      assert.equal(input.senderRole, undefined);
      return {
        message: { messageId: 1, text: input.text },
        roomId: 9,
        broadcast: true,
      };
    },
    async isDriverAuthorizedForBooking() {
      return true;
    },
  };

  const originalGet = require('../src/helpers/container').get;
  require('../src/helpers/container').get = (name) => {
    if (name === 'chatService') return chatService;
    return originalGet(name);
  };

  registerChatHandlers(io, socket);
  await socket.handlers['chat:send']({
    bookingNumber: 'TX202607010001',
    text: 'hello',
    clientMessageId: '88888888-8888-4888-8888-888888888888',
    senderRole: 'ADMIN',
    senderUserId: 999,
  });

  require('../src/helpers/container').get = originalGet;
  assert.equal(io.emitted.length, 1);
});

test('chat:join rejects inaccessible booking through service', async () => {
  const socket = buildSocket();
  const io = buildIo();
  const chatService = {
    async getRoom() {
      const err = new Error('Chat is not accessible');
      err.errorCode = ERROR_CODES.CHAT_NOT_ACCESSIBLE;
      throw err;
    },
  };
  const originalGet = require('../src/helpers/container').get;
  require('../src/helpers/container').get = (name) => {
    if (name === 'chatService') return chatService;
    return originalGet(name);
  };
  registerChatHandlers(io, socket);
  await socket.handlers['chat:join']({ bookingNumber: 'TX202607010099' });
  require('../src/helpers/container').get = originalGet;
  assert.equal(socket.emitted[0].payload.code, ERROR_CODES.CHAT_NOT_ACCESSIBLE);
});

test('old reassigned driver is evicted before broadcast', async () => {
  const oldDriverSocket = buildSocket({
    id: 'old-driver',
    authUser: { id: 5, role: ROLES.DRIVER },
    activeChatRoomId: 9,
  });
  const roomKey = socketRoomName(9);
  const io = buildIo({ [roomKey]: [oldDriverSocket] });
  const chatService = {
    async sendMessage() {
      return {
        message: { messageId: 2, text: 'new' },
        roomId: 9,
        broadcast: true,
      };
    },
    async isDriverAuthorizedForBooking(_bookingNumber, driverUserId) {
      return driverUserId !== 5;
    },
  };

  await evictUnauthorizedDriverSockets(io, 9, 'TX202607010001', chatService);
  assert.equal(oldDriverSocket.joinedRooms.has(roomKey), false);
  assert.equal(oldDriverSocket.emitted[0].payload.code, ERROR_CODES.CHAT_NOT_ACCESSIBLE);
});

test('chat:send failure for unauthorized driver leaves room', async () => {
  const socket = buildSocket({
    authUser: { id: 5, role: ROLES.DRIVER },
    activeChatRoomId: 9,
    activeBookingNumber: 'TX202607010001',
  });
  socket.joinedRooms.add(socketRoomName(9));
  const io = buildIo();
  const chatService = {
    async sendMessage() {
      const err = new Error('Chat is not accessible');
      err.errorCode = ERROR_CODES.CHAT_NOT_ACCESSIBLE;
      throw err;
    },
  };

  const originalGet = require('../src/helpers/container').get;
  require('../src/helpers/container').get = (name) => {
    if (name === 'chatService') return chatService;
    return originalGet(name);
  };

  registerChatHandlers(io, socket);
  await socket.handlers['chat:send']({
    bookingNumber: 'TX202607010001',
    text: 'hello',
    clientMessageId: '88888888-8888-4888-8888-888888888888',
  });

  require('../src/helpers/container').get = originalGet;
  assert.equal(socket.joinedRooms.has(socketRoomName(9)), false);
});

test('chat:read emits read-updated with unread count', async () => {
  const io = buildIo();
  const socket = buildSocket({
    activeBookingNumber: 'TX202607010001',
  });
  const chatService = {
    async markRead() {
      return { upToMessageId: 3, unreadCount: 0, roomId: 9 };
    },
  };

  const originalGet = require('../src/helpers/container').get;
  require('../src/helpers/container').get = (name) => {
    if (name === 'chatService') return chatService;
    return originalGet(name);
  };

  registerChatHandlers(io, socket);
  await socket.handlers['chat:read']({ upToMessageId: 3 });

  require('../src/helpers/container').get = originalGet;
  assert.equal(io.emitted[0].event, 'chat:read-updated');
  assert.equal(io.emitted[0].payload.unreadCount, 0);
});

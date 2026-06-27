const logger = require('../../utils/logger');
const container = require('../../helpers/container');
const ERROR_CODES = require('../../constants/errorCodes');
const ROLES = require('../../constants/roles');

function socketRoomName(roomId) {
  return `chat:${roomId}`;
}

function mapSocketError(err) {
  return {
    code: err.errorCode ?? ERROR_CODES.INTERNAL_SERVER_ERROR,
    message: err.message ?? 'Chat request failed',
  };
}

async function leaveChatRoom(socket, roomId) {
  if (!roomId) return;
  await socket.leave(socketRoomName(roomId));
  if (socket.data.activeChatRoomId === roomId) {
    socket.data.activeChatRoomId = null;
    socket.data.activeBookingNumber = null;
  }
}

async function evictUnauthorizedDriverSockets(io, roomId, bookingNumber, chatService) {
  const roomKey = socketRoomName(roomId);
  const sockets = await io.in(roomKey).fetchSockets();
  for (const remoteSocket of sockets) {
    const authUser = remoteSocket.data.authUser;
    if (!authUser || authUser.role !== ROLES.DRIVER) continue;
    const allowed = await chatService.isDriverAuthorizedForBooking(bookingNumber, authUser.id);
    if (!allowed) {
      await remoteSocket.leave(roomKey);
      remoteSocket.emit('chat:error', {
        code: ERROR_CODES.CHAT_NOT_ACCESSIBLE,
        message: 'Chat is not accessible',
      });
    }
  }
}

function registerChatHandlers(io, socket) {
  const getChatService = () => container.get('chatService');

  socket.on('chat:join', async (payload = {}, ack) => {
    try {
      const bookingNumber = String(payload.bookingNumber ?? '').trim();
      if (!bookingNumber) {
        throw new Error('bookingNumber required');
      }
      const authUser = socket.data.authUser ?? null;
      const guestAccessToken = socket.data.guestAccessToken ?? null;
      const room = await getChatService().getRoom(bookingNumber, authUser, guestAccessToken);
      const roomKey = socketRoomName(room.roomId);
      if (socket.data.activeChatRoomId && socket.data.activeChatRoomId !== room.roomId) {
        await leaveChatRoom(socket, socket.data.activeChatRoomId);
      }
      await socket.join(roomKey);
      socket.data.activeChatRoomId = room.roomId;
      socket.data.activeBookingNumber = bookingNumber;
      const response = { room, roomKey };
      socket.emit('chat:joined', response);
      if (typeof ack === 'function') ack({ ok: true, ...response });
    } catch (err) {
      logger.warn('chat:join failed', { error: err.message, socketId: socket.id });
      if (socket.data.activeChatRoomId) {
        await leaveChatRoom(socket, socket.data.activeChatRoomId);
      }
      const mapped = mapSocketError(err);
      socket.emit('chat:error', mapped);
      if (typeof ack === 'function') ack({ ok: false, error: mapped });
    }
  });

  socket.on('chat:leave', async (payload = {}) => {
    const roomId = payload.roomId ?? socket.data.activeChatRoomId;
    await leaveChatRoom(socket, roomId);
  });

  socket.on('chat:send', async (payload = {}, ack) => {
    try {
      const bookingNumber = String(
        payload.bookingNumber ?? socket.data.activeBookingNumber ?? '',
      ).trim();
      if (!bookingNumber) {
        throw new Error('bookingNumber required');
      }
      const authUser = socket.data.authUser ?? null;
      const guestAccessToken = socket.data.guestAccessToken ?? null;
      const result = await getChatService().sendMessage(
        bookingNumber,
        authUser,
        guestAccessToken,
        {
          text: payload.text,
          clientMessageId: payload.clientMessageId,
        },
      );
      if (result.broadcast) {
        await evictUnauthorizedDriverSockets(
          io,
          result.roomId,
          bookingNumber,
          getChatService(),
        );
        io.to(socketRoomName(result.roomId)).emit('chat:message', {
          bookingNumber,
          roomId: result.roomId,
          message: result.message,
        });
      }
      if (typeof ack === 'function') ack({ ok: true, message: result.message });
    } catch (err) {
      logger.warn('chat:send failed', { error: err.message, socketId: socket.id });
      const mapped = mapSocketError(err);
      if (mapped.code === ERROR_CODES.CHAT_NOT_ACCESSIBLE && socket.data.activeChatRoomId) {
        await leaveChatRoom(socket, socket.data.activeChatRoomId);
      }
      socket.emit('chat:error', mapped);
      if (typeof ack === 'function') ack({ ok: false, error: mapped });
    }
  });

  socket.on('chat:read', async (payload = {}, ack) => {
    try {
      const bookingNumber = String(
        payload.bookingNumber ?? socket.data.activeBookingNumber ?? '',
      ).trim();
      const authUser = socket.data.authUser ?? null;
      const guestAccessToken = socket.data.guestAccessToken ?? null;
      const data = await getChatService().markRead(
        bookingNumber,
        authUser,
        guestAccessToken,
        payload,
      );
      io.to(socketRoomName(data.roomId)).emit('chat:read-updated', {
        bookingNumber,
        roomId: data.roomId,
        upToMessageId: data.upToMessageId,
        unreadCount: data.unreadCount,
        participantSocketId: socket.id,
      });
      if (typeof ack === 'function') ack({ ok: true, ...data });
    } catch (err) {
      const mapped = mapSocketError(err);
      socket.emit('chat:error', mapped);
      if (typeof ack === 'function') ack({ ok: false, error: mapped });
    }
  });
}

module.exports = {
  registerChatHandlers,
  socketRoomName,
  evictUnauthorizedDriverSockets,
  leaveChatRoom,
};

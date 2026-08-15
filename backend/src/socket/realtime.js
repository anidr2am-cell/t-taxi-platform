const ROLES = require('../constants/roles');
const logger = require('../utils/logger');

let ioInstance = null;

const DRIVER_ALL_ROOM = 'drivers:open-calls';

function driverUserRoom(userId) {
  return `driver:user:${userId}`;
}

function setRealtimeIo(io) {
  ioInstance = io;
}

function getRealtimeIo() {
  return ioInstance;
}

async function joinDriverRooms(socket) {
  const authUser = socket.data.authUser;
  if (!authUser || authUser.role !== ROLES.DRIVER) return false;
  await socket.join(DRIVER_ALL_ROOM);
  const room = driverUserRoom(authUser.id);
  await socket.join(room);
  // TEMP SOCKET DEBUG — remove after M2 STANDARD realtime E2E diagnosis
  logger.info('[SOCKET DEBUG] subscribe', {
    userId: authUser.id,
    room,
    socketId: socket.id ? String(socket.id).slice(0, 8) : null,
  });
  return true;
}

function emitDriverCallAvailable(driverUserId, payload) {
  const room = driverUserRoom(driverUserId);
  const bookingNumber = payload?.bookingNumber ?? null;
  // TEMP SOCKET DEBUG — remove after M2 STANDARD realtime E2E diagnosis
  if (!ioInstance) {
    logger.info('[SOCKET DEBUG] emit driver:call:new skipped io unavailable', {
      bookingNumber,
      targetUserId: driverUserId,
      room,
    });
    return;
  }
  logger.info('[SOCKET DEBUG] emit driver:call:new', {
    bookingNumber,
    targetUserId: driverUserId,
    room,
  });
  ioInstance.to(room).emit('driver:call:new', payload);
}

function emitDriverCallClaimed(payload) {
  if (!ioInstance) return;
  ioInstance.to(DRIVER_ALL_ROOM).emit('driver:call:claimed', payload);
}

function emitDriverCallConfirmed(driverUserId, payload) {
  if (!ioInstance) return;
  ioInstance.to(driverUserRoom(driverUserId)).emit('driver:call:confirmed', payload);
}

function emitDriverAssignmentReleased(driverUserId, payload) {
  if (!ioInstance) return;
  ioInstance.to(driverUserRoom(driverUserId)).emit('driver:assignment:released', payload);
}

function emitDriverUrgentCallEtaRequired(driverUserId, payload) {
  if (!ioInstance) return;
  ioInstance.to(driverUserRoom(driverUserId)).emit('driver:urgent-call:eta-required', payload);
}

function emitDriverUrgentCallLocked(payload) {
  if (!ioInstance) return;
  ioInstance.to(DRIVER_ALL_ROOM).emit('driver:urgent-call:locked', payload);
}

function guestBookingRoom(bookingId) {
  return `guest_booking:${bookingId}`;
}

function emitBookingUrgentNegotiationEtaProposed(bookingId, payload) {
  if (!ioInstance || !bookingId) return;
  ioInstance.to(guestBookingRoom(bookingId)).emit('booking:urgent-negotiation:eta-proposed', payload);
}

function emitDriverUrgentCallConfirmed(driverUserId, payload) {
  if (!ioInstance) return;
  ioInstance.to(driverUserRoom(driverUserId)).emit('driver:urgent-call:confirmed', payload);
}

function emitBookingUrgentNegotiationConfirmed(bookingId, payload) {
  if (!ioInstance || !bookingId) return;
  ioInstance.to(guestBookingRoom(bookingId)).emit('booking:urgent-negotiation:confirmed', payload);
}

function emitDriverUrgentCallRoundEnded(driverUserId, payload) {
  if (!ioInstance) return;
  ioInstance.to(driverUserRoom(driverUserId)).emit('driver:urgent-call:round-ended', payload);
}

function emitDriverUrgentCallUnlocked(payload) {
  if (!ioInstance) return;
  ioInstance.to(DRIVER_ALL_ROOM).emit('driver:urgent-call:unlocked', payload);
}

function emitDriverUrgentCallNew(payload) {
  const bookingNumber = payload?.bookingNumber ?? null;
  const negotiationId = payload?.negotiationId ?? null;
  // TEMP SOCKET DEBUG — remove after M2 URGENT realtime E2E diagnosis
  if (!ioInstance) {
    logger.info('[SOCKET DEBUG] emit driver:urgent-call:new skipped io unavailable', {
      bookingNumber,
      negotiationId,
      room: DRIVER_ALL_ROOM,
    });
    return;
  }
  logger.info('[SOCKET DEBUG] emit driver:urgent-call:new', {
    bookingNumber,
    negotiationId,
    room: DRIVER_ALL_ROOM,
  });
  ioInstance.to(DRIVER_ALL_ROOM).emit('driver:urgent-call:new', payload);
}

function emitDriverUrgentCallCancelled(payload) {
  if (!ioInstance) return;
  ioInstance.to(DRIVER_ALL_ROOM).emit('driver:urgent-call:cancelled', payload);
}

function emitBookingUrgentNegotiationCancelled(bookingId, payload) {
  if (!ioInstance || !bookingId) return;
  ioInstance.to(guestBookingRoom(bookingId)).emit('booking:urgent-negotiation:cancelled', payload);
}

function emitBookingUrgentNegotiationExpired(bookingId, payload) {
  if (!ioInstance || !bookingId) return;
  ioInstance.to(guestBookingRoom(bookingId)).emit('booking:urgent-negotiation:expired', payload);
}

module.exports = {
  DRIVER_ALL_ROOM,
  driverUserRoom,
  guestBookingRoom,
  setRealtimeIo,
  getRealtimeIo,
  joinDriverRooms,
  emitDriverCallAvailable,
  emitDriverCallClaimed,
  emitDriverCallConfirmed,
  emitDriverAssignmentReleased,
  emitDriverUrgentCallEtaRequired,
  emitDriverUrgentCallLocked,
  emitBookingUrgentNegotiationEtaProposed,
  emitDriverUrgentCallConfirmed,
  emitBookingUrgentNegotiationConfirmed,
  emitDriverUrgentCallRoundEnded,
  emitDriverUrgentCallUnlocked,
  emitDriverUrgentCallNew,
  emitDriverUrgentCallCancelled,
  emitBookingUrgentNegotiationCancelled,
  emitBookingUrgentNegotiationExpired,
};

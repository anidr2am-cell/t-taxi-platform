const ROLES = require('../constants/roles');

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
  await socket.join(driverUserRoom(authUser.id));
  return true;
}

function emitDriverCallAvailable(driverUserId, payload) {
  if (!ioInstance) return;
  ioInstance.to(driverUserRoom(driverUserId)).emit('driver:call:new', payload);
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

module.exports = {
  DRIVER_ALL_ROOM,
  driverUserRoom,
  setRealtimeIo,
  getRealtimeIo,
  joinDriverRooms,
  emitDriverCallAvailable,
  emitDriverCallClaimed,
  emitDriverCallConfirmed,
  emitDriverAssignmentReleased,
};

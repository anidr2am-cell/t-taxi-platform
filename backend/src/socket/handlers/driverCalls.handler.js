const ERROR_CODES = require('../../constants/errorCodes');
const ROLES = require('../../constants/roles');
const { joinDriverRooms, DRIVER_ALL_ROOM } = require('../realtime');

function registerDriverCallHandlers(_io, socket) {
  if (socket.data.authUser?.role === ROLES.DRIVER) {
    joinDriverRooms(socket).catch(() => {});
  }

  socket.on('driver:calls:subscribe', async (_payload = {}, ack) => {
    try {
      const authUser = socket.data.authUser;
      if (!authUser || authUser.role !== ROLES.DRIVER) {
        const err = new Error('Driver authentication required');
        err.errorCode = ERROR_CODES.FORBIDDEN;
        throw err;
      }
      await joinDriverRooms(socket);
      if (typeof ack === 'function') ack({ ok: true, room: DRIVER_ALL_ROOM });
    } catch (err) {
      const mapped = {
        code: err.errorCode ?? ERROR_CODES.INTERNAL_SERVER_ERROR,
        message: err.message ?? 'Driver call subscription failed',
      };
      socket.emit('driver:calls:error', mapped);
      if (typeof ack === 'function') ack({ ok: false, error: mapped });
    }
  });
}

module.exports = {
  registerDriverCallHandlers,
};

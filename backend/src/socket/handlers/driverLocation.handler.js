const container = require('../../helpers/container');
const ERROR_CODES = require('../../constants/errorCodes');
const ROLES = require('../../constants/roles');
const {
  DRIVER_LOCATION_RATE_WINDOW_MS,
  DRIVER_LOCATION_RATE_MAX,
} = require('../../constants/driverLocation');

const ADMIN_DRIVER_LOCATION_ROOM = 'drivers:locations:admin';

function bookingDriverLocationRoom(bookingId) {
  return `booking:${bookingId}:driver-location`;
}

function mapSocketError(err) {
  return {
    code: err.errorCode ?? ERROR_CODES.INTERNAL_SERVER_ERROR,
    message: err.message ?? 'Driver location request failed',
  };
}

function consumeLocationRate(socket) {
  const now = Date.now();
  const bucket = socket.data.driverLocationRate ?? { count: 0, resetAt: now + DRIVER_LOCATION_RATE_WINDOW_MS };
  if (bucket.resetAt <= now) {
    bucket.count = 0;
    bucket.resetAt = now + DRIVER_LOCATION_RATE_WINDOW_MS;
  }
  bucket.count += 1;
  socket.data.driverLocationRate = bucket;
  return bucket.count <= DRIVER_LOCATION_RATE_MAX;
}

function registerDriverLocationHandlers(io, socket) {
  const getService = () => container.get('driverLocationService');

  socket.on('driver:location:update', async (payload = {}, ack) => {
    try {
      const authUser = socket.data.authUser;
      if (!authUser || authUser.role !== ROLES.DRIVER) {
        const err = new Error('Driver authentication required');
        err.errorCode = ERROR_CODES.FORBIDDEN;
        throw err;
      }
      if (!consumeLocationRate(socket)) {
        const err = new Error('Too many location updates');
        err.errorCode = ERROR_CODES.RATE_LIMIT;
        throw err;
      }
      const result = await getService().updateDriverLocation(authUser.id, payload);
      const snapshot = await getService().listAdminLocations({ onlineOnly: false });
      const changed = snapshot.items.find((item) => item.driverId === result.driverId) ?? null;
      if (changed) {
        io.to(ADMIN_DRIVER_LOCATION_ROOM).emit('driver:location:changed', changed);
        for (const bookingId of result.bookingIds) {
          io.to(bookingDriverLocationRoom(bookingId)).emit('booking:driver-location:changed', {
            bookingId,
            available: true,
            driver: changed,
          });
        }
      }
      if (typeof ack === 'function') ack({ ok: true, accepted: true });
    } catch (err) {
      const mapped = mapSocketError(err);
      socket.emit('driver-location:error', mapped);
      if (typeof ack === 'function') ack({ ok: false, error: mapped });
    }
  });

  socket.on('driver-location:admin:subscribe', async (_payload = {}, ack) => {
    try {
      const authUser = socket.data.authUser;
      if (!authUser || ![ROLES.ADMIN, ROLES.SUPER_ADMIN].includes(authUser.role)) {
        const err = new Error('Admin authentication required');
        err.errorCode = ERROR_CODES.FORBIDDEN;
        throw err;
      }
      await socket.join(ADMIN_DRIVER_LOCATION_ROOM);
      if (typeof ack === 'function') ack({ ok: true, room: ADMIN_DRIVER_LOCATION_ROOM });
    } catch (err) {
      const mapped = mapSocketError(err);
      socket.emit('driver-location:error', mapped);
      if (typeof ack === 'function') ack({ ok: false, error: mapped });
    }
  });

  socket.on('booking:driver-location:subscribe', async (payload = {}, ack) => {
    try {
      const bookingId = Number(payload.bookingId);
      if (!Number.isInteger(bookingId) || bookingId <= 0) {
        const err = new Error('bookingId required');
        err.errorCode = ERROR_CODES.VALIDATION_ERROR;
        throw err;
      }
      await getService().getGuestDriverLocation(bookingId, socket.data.guestAccessToken);
      const room = bookingDriverLocationRoom(bookingId);
      await socket.join(room);
      if (typeof ack === 'function') ack({ ok: true, room });
    } catch (err) {
      const mapped = mapSocketError(err);
      socket.emit('driver-location:error', mapped);
      if (typeof ack === 'function') ack({ ok: false, error: mapped });
    }
  });
}

module.exports = {
  registerDriverLocationHandlers,
  bookingDriverLocationRoom,
  ADMIN_DRIVER_LOCATION_ROOM,
};

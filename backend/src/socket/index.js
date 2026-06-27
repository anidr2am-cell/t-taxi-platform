/**
 * socket/index.js — Socket.IO bootstrap
 */
const logger = require('../utils/logger');
const container = require('../helpers/container');
const ERROR_CODES = require('../constants/errorCodes');
const { registerChatHandlers } = require('./handlers/chat.handler');

function rejectUnauthorized(next, message = 'Unauthorized') {
  const err = new Error(message);
  err.data = { code: ERROR_CODES.UNAUTHORIZED };
  next(err);
}

function initSocket(io) {
  io.use((socket, next) => {
    if (socket.handshake.query?.token || socket.handshake.query?.guestAccessToken) {
      return rejectUnauthorized(next, 'Token query parameters are not allowed');
    }

    const auth = socket.handshake.auth ?? {};
    const token = auth.token ?? auth.accessToken ?? null;
    const guestAccessToken = auth.guestAccessToken ?? null;

    if (!token && !guestAccessToken) {
      return rejectUnauthorized(next);
    }

    try {
      if (token) {
        const authService = container.get('authService');
        socket.data.authUser = authService.verifyAccessToken(token);
      } else {
        socket.data.authUser = null;
      }
      socket.data.guestAccessToken = guestAccessToken ? String(guestAccessToken).trim() : null;
      return next();
    } catch (err) {
      return rejectUnauthorized(next);
    }
  });

  io.on('connection', (socket) => {
    logger.info('Socket connected', { id: socket.id });

    registerChatHandlers(io, socket);

    socket.on('disconnect', (reason) => {
      logger.debug('Socket disconnected', { id: socket.id, reason });
    });
  });

  logger.info('Socket.IO initialized');
}

module.exports = {
  initSocket,
};

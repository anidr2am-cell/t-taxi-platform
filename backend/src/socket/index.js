/**
 * socket/index.js — Socket.IO bootstrap
 */
const logger = require('../utils/logger');
const { registerChatHandlers } = require('./handlers/chat.handler');

function initSocket(io) {
  io.use((socket, next) => {
    // TODO: JWT from socket.handshake.auth.token
    // const token = socket.handshake.auth?.token;
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

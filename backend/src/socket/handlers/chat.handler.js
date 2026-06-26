/**
 * socket/handlers/chat.handler.js — Chat events (skeleton)
 *
 * OpenAPI WebSocket events:
 * - join_room, send_message, mark_read
 * - message_history, new_message, messages_read
 */
const logger = require('../../utils/logger');

function registerChatHandlers(io, socket) {
  socket.on('join_room', (payload) => {
    logger.debug('join_room (not implemented)', { payload, socketId: socket.id });
    // TODO: validate room access, socket.join(roomCode), emit message_history
  });

  socket.on('send_message', (payload) => {
    logger.debug('send_message (not implemented)', { payload });
    // TODO: chatService.saveMessage → io.to(room).emit('new_message', msg)
  });

  socket.on('mark_read', (payload) => {
    logger.debug('mark_read (not implemented)', { payload });
  });
}

module.exports = {
  registerChatHandlers,
};

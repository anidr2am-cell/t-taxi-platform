const express = require('express');
const chatController = require('../controllers/chat.controller');
const validate = require('../middlewares/validate.middleware');
const { authMiddleware, optionalAuthMiddleware } = require('../middlewares/auth.middleware');
const roleMiddleware = require('../middlewares/role.middleware');
const ROLES = require('../constants/roles');
const {
  bookingNumberParamsSchema,
  chatMessageListQuerySchema,
  sendChatMessageSchema,
  markChatReadSchema,
  adminChatListQuerySchema,
  adminChatMessageIdParamsSchema,
  adminChatMessageHideSchema,
  adminChatThreadArchiveSchema,
} = require('../validators/chat.validator');

const router = express.Router();

router.get(
  '/chats',
  authMiddleware,
  roleMiddleware([ROLES.ADMIN, ROLES.SUPER_ADMIN]),
  validate({ query: adminChatListQuerySchema }),
  chatController.listAdminChats,
);

router.post(
  '/chats/messages/:id/hide',
  authMiddleware,
  roleMiddleware([ROLES.ADMIN, ROLES.SUPER_ADMIN]),
  validate({ params: adminChatMessageIdParamsSchema, body: adminChatMessageHideSchema }),
  chatController.hideAdminChatMessage,
);

router.post(
  '/chats/messages/:id/restore',
  authMiddleware,
  roleMiddleware([ROLES.ADMIN, ROLES.SUPER_ADMIN]),
  validate({ params: adminChatMessageIdParamsSchema }),
  chatController.restoreAdminChatMessage,
);

router.post(
  '/chats/archive',
  authMiddleware,
  roleMiddleware([ROLES.ADMIN, ROLES.SUPER_ADMIN]),
  validate({ body: adminChatThreadArchiveSchema }),
  chatController.archiveAdminChatThreads,
);

router.post(
  '/chats/:bookingNumber/restore',
  authMiddleware,
  roleMiddleware([ROLES.ADMIN, ROLES.SUPER_ADMIN]),
  validate({ params: bookingNumberParamsSchema }),
  chatController.restoreAdminChatThread,
);

router.get(
  '/chats/:bookingNumber',
  authMiddleware,
  roleMiddleware([ROLES.ADMIN, ROLES.SUPER_ADMIN]),
  validate({ params: bookingNumberParamsSchema }),
  chatController.getAdminChat,
);

router.get(
  '/chats/:bookingNumber/messages',
  authMiddleware,
  roleMiddleware([ROLES.ADMIN, ROLES.SUPER_ADMIN]),
  validate({ params: bookingNumberParamsSchema, query: chatMessageListQuerySchema }),
  chatController.listAdminChatMessages,
);

router.post(
  '/chats/:bookingNumber/messages',
  authMiddleware,
  roleMiddleware([ROLES.ADMIN, ROLES.SUPER_ADMIN]),
  validate({ params: bookingNumberParamsSchema, body: sendChatMessageSchema }),
  chatController.sendAdminChatMessage,
);

router.post(
  '/chats/:bookingNumber/read',
  authMiddleware,
  roleMiddleware([ROLES.ADMIN, ROLES.SUPER_ADMIN]),
  validate({ params: bookingNumberParamsSchema, body: markChatReadSchema }),
  chatController.markAdminChatRead,
);

module.exports = router;

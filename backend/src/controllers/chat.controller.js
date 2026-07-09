const asyncHandler = require("../utils/asyncHandler");
const { success, paginate } = require("../utils/apiResponse");
const container = require("../helpers/container");
const {
  extractGuestAccessTokenFromHeader,
} = require("../utils/guestAccess.util");

const getChatService = () => container.get("chatService");

const getBookingChat = asyncHandler(async (req, res) => {
  const data = await getChatService().getRoom(
    req.params.bookingNumber,
    req.user ?? null,
    extractGuestAccessTokenFromHeader(req),
  );
  return success(res, data);
});

const listBookingChatMessages = asyncHandler(async (req, res) => {
  const data = await getChatService().listMessages(
    req.params.bookingNumber,
    req.user ?? null,
    extractGuestAccessTokenFromHeader(req),
    req.query,
  );
  return success(res, data);
});

const sendBookingChatMessage = asyncHandler(async (req, res) => {
  const result = await getChatService().sendMessage(
    req.params.bookingNumber,
    req.user ?? null,
    extractGuestAccessTokenFromHeader(req),
    req.body,
  );
  return success(res, result.message, "Created", 201);
});

const sendBookingPickupAlert = asyncHandler(async (req, res) => {
  const data = await getChatService().sendPickupAlert(
    req.params.bookingNumber,
    req.user ?? null,
    extractGuestAccessTokenFromHeader(req),
  );
  return success(res, data, data.alreadySent ? "Already sent" : "Created", 201);
});

const markBookingChatRead = asyncHandler(async (req, res) => {
  const data = await getChatService().markRead(
    req.params.bookingNumber,
    req.user ?? null,
    extractGuestAccessTokenFromHeader(req),
    req.body,
  );
  return success(res, data);
});

const listAdminChats = asyncHandler(async (req, res) => {
  const data = await getChatService().listAdminChats(req.user, req.query);
  return paginate(res, {
    page: data.page,
    pageSize: data.pageSize,
    total: data.total,
    items: data.items,
  });
});

const getAdminChat = asyncHandler(async (req, res) => {
  const data = await getChatService().getAdminRoom(
    req.params.bookingNumber,
    req.user,
  );
  return success(res, data);
});

const listAdminChatMessages = asyncHandler(async (req, res) => {
  const data = await getChatService().listAdminMessages(
    req.params.bookingNumber,
    req.user,
    req.query,
  );
  return success(res, data);
});

const sendAdminChatMessage = asyncHandler(async (req, res) => {
  const result = await getChatService().sendAdminMessage(
    req.params.bookingNumber,
    req.user,
    req.body,
  );
  return success(res, result.message, "Created", 201);
});

const markAdminChatRead = asyncHandler(async (req, res) => {
  const data = await getChatService().markAdminRead(
    req.params.bookingNumber,
    req.user,
    req.body,
  );
  return success(res, data);
});

module.exports = {
  getBookingChat,
  listBookingChatMessages,
  sendBookingChatMessage,
  sendBookingPickupAlert,
  markBookingChatRead,
  listAdminChats,
  getAdminChat,
  listAdminChatMessages,
  sendAdminChatMessage,
  markAdminChatRead,
};

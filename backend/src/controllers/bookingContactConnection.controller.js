const container = require('../helpers/container');

function guestAccessTokenFromRequest(req) {
  return req.headers['x-guest-access-token']
    || req.body?.guestAccessToken
    || null;
}

async function getContactConnection(req, res, next) {
  try {
    const service = container.get('bookingContactConnectionService');
    const data = await service.getConnectionStatus(
      req.params.bookingNumber,
      req.user ?? null,
      guestAccessTokenFromRequest(req),
    );
    res.json({ success: true, data });
  } catch (err) {
    next(err);
  }
}

async function getContactChannelSettings(req, res, next) {
  try {
    const service = container.get('bookingContactConnectionService');
    const data = await service.getPublicSettings();
    res.json({ success: true, data });
  } catch (err) {
    next(err);
  }
}

async function startContactConnection(req, res, next) {
  try {
    const service = container.get('bookingContactConnectionService');
    const data = await service.startConnection(
      req.params.bookingNumber,
      req.body.channel,
      req.user ?? null,
      guestAccessTokenFromRequest(req),
    );
    res.json({ success: true, data });
  } catch (err) {
    next(err);
  }
}

async function confirmContactSent(req, res, next) {
  try {
    const service = container.get('bookingContactConnectionService');
    const data = await service.confirmSent(
      req.params.bookingNumber,
      req.user ?? null,
      guestAccessTokenFromRequest(req),
    );
    res.json({ success: true, data });
  } catch (err) {
    next(err);
  }
}

async function adminVerifyContact(req, res, next) {
  try {
    const service = container.get('bookingContactConnectionService');
    const data = await service.adminVerify(
      req.params.bookingNumber,
      req.user.id,
    );
    res.json({ success: true, data });
  } catch (err) {
    next(err);
  }
}

module.exports = {
  getContactConnection,
  getContactChannelSettings,
  startContactConnection,
  confirmContactSent,
  adminVerifyContact,
};

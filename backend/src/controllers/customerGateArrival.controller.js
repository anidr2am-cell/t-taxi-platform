const container = require('../helpers/container');
const handle = (send) => async (req, res, next) => {
  try {
    const data = await container.get('customerGateArrivalService').run(
      req.params.bookingNumber, req.user ?? null, req.headers['x-guest-access-token'] ?? null, send,
    );
    res.set('Cache-Control', 'no-store');
    res.json({ success: true, data });
  } catch (err) { next(err); }
};
module.exports = { status: handle(false), send: handle(true) };

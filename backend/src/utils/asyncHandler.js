/**
 * utils/asyncHandler.js — Wrap async route handlers
 *
 * try/catch를 every route에 쓰지 않고 error middleware로 전달
 *
 * 사용:
 * router.get('/x', asyncHandler(async (req, res) => { ... }));
 */
function asyncHandler(fn) {
  return (req, res, next) => {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
}

module.exports = asyncHandler;

const express = require('express');
const authController = require('../controllers/auth.controller');
const validate = require('../middlewares/validate.middleware');
const { authMiddleware } = require('../middlewares/auth.middleware');
const {
  loginIpRateLimit,
  loginIdentifierRateLimit,
  registerRateLimit,
  refreshRateLimit,
  passwordResetRequestRateLimit,
  passwordResetConfirmRateLimit,
} = require('../middlewares/authRateLimit.middleware');
const {
  registerSchema,
  loginSchema,
  refreshSchema,
  logoutSchema,
  googleSocialLoginSchema,
  kakaoSocialLoginSchema,
  lineSocialLoginSchema,
  driverPasswordResetRequestSchema,
  driverPasswordResetConfirmSchema,
} = require('../validators/auth.validator');

const router = express.Router();

router.post(
  '/register',
  registerRateLimit,
  validate({ body: registerSchema }),
  authController.register,
);
router.post(
  '/login',
  loginIpRateLimit,
  loginIdentifierRateLimit,
  validate({ body: loginSchema }),
  authController.login,
);
router.post(
  '/driver/password-reset/request',
  passwordResetRequestRateLimit,
  validate({ body: driverPasswordResetRequestSchema }),
  authController.requestDriverPasswordReset,
);
router.post(
  '/driver/password-reset/confirm',
  passwordResetConfirmRateLimit,
  validate({ body: driverPasswordResetConfirmSchema }),
  authController.confirmDriverPasswordReset,
);
router.post(
  '/social/google',
  loginIpRateLimit,
  validate({ body: googleSocialLoginSchema }),
  authController.googleSocialLogin,
);
router.post(
  '/social/kakao',
  loginIpRateLimit,
  validate({ body: kakaoSocialLoginSchema }),
  authController.kakaoSocialLogin,
);
router.post(
  '/social/line',
  loginIpRateLimit,
  validate({ body: lineSocialLoginSchema }),
  authController.lineSocialLogin,
);
router.post(
  '/refresh',
  refreshRateLimit,
  validate({ body: refreshSchema }),
  authController.refresh,
);
router.post('/logout', authMiddleware, validate({ body: logoutSchema }), authController.logout);
router.get('/me', authMiddleware, authController.me);

module.exports = router;

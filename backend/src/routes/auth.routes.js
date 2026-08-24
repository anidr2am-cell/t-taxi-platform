const express = require('express');
const authController = require('../controllers/auth.controller');
const validate = require('../middlewares/validate.middleware');
const { authMiddleware } = require('../middlewares/auth.middleware');
const {
  loginIpRateLimit,
  loginIdentifierRateLimit,
  registerRateLimit,
  refreshRateLimit,
} = require('../middlewares/authRateLimit.middleware');
const {
  registerSchema,
  loginSchema,
  refreshSchema,
  logoutSchema,
  googleSocialLoginSchema,
  kakaoSocialLoginSchema,
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
  '/refresh',
  refreshRateLimit,
  validate({ body: refreshSchema }),
  authController.refresh,
);
router.post('/logout', authMiddleware, validate({ body: logoutSchema }), authController.logout);
router.get('/me', authMiddleware, authController.me);

module.exports = router;

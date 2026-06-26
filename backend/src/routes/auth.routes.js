const express = require('express');
const authController = require('../controllers/auth.controller');
const validate = require('../middlewares/validate.middleware');
const { authMiddleware } = require('../middlewares/auth.middleware');
const {
  registerSchema,
  loginSchema,
  refreshSchema,
  logoutSchema,
} = require('../validators/auth.validator');

const router = express.Router();

router.post('/register', validate({ body: registerSchema }), authController.register);
router.post('/login', validate({ body: loginSchema }), authController.login);
router.post('/refresh', validate({ body: refreshSchema }), authController.refresh);
router.post('/logout', authMiddleware, validate({ body: logoutSchema }), authController.logout);
router.get('/me', authMiddleware, authController.me);

module.exports = router;

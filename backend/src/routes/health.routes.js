/**
 * routes/health.routes.js — Infrastructure health (not business API)
 */
const express = require('express');
const healthController = require('../controllers/health.controller');

const router = express.Router();

router.get('/', healthController.getHealth);
router.get('/readiness', healthController.getReadiness);

module.exports = router;

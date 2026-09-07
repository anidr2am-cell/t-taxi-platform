const express = require('express');
const controller = require('../controllers/platformSettings.controller');
const router = express.Router();

router.get('/public', controller.getPublic);
router.get('/guest-lookup-inquiry', controller.getGuestLookupInquiryPublic);
router.get('/assets/:kind', controller.getAsset);

module.exports = router;

const DELIVERY_STATUS = require('../constants/notificationDeliveryStatus');
const NOTIFICATION_CHANNELS = require('../constants/notificationChannels');
const config = require('../config/env');

class InAppNotificationAdapter {
  async send(_notification, _recipient) {
    return { status: DELIVERY_STATUS.DELIVERED };
  }
}

class EmailNotificationAdapter {
  isConfigured() {
    return Boolean(process.env.SMTP_HOST && process.env.SMTP_USER);
  }

  async send(_notification, _recipient) {
    if (!this.isConfigured()) {
      return { status: DELIVERY_STATUS.SKIPPED, error: 'SMTP not configured' };
    }
    return { status: DELIVERY_STATUS.SKIPPED, error: 'Email delivery not implemented in MVP' };
  }
}

class FcmNotificationAdapter {
  isConfigured() {
    const fb = config.firebase;
    return Boolean(
      fb.projectId && (fb.clientEmail || fb.serviceAccountPath),
    );
  }

  async send(_notification, _recipient) {
    if (!this.isConfigured()) {
      return { status: DELIVERY_STATUS.SKIPPED, error: 'FCM not configured' };
    }
    return { status: DELIVERY_STATUS.SKIPPED, error: 'FCM delivery not implemented in MVP' };
  }
}

function createDeliveryAdapters() {
  return {
    [NOTIFICATION_CHANNELS.IN_APP]: new InAppNotificationAdapter(),
    [NOTIFICATION_CHANNELS.EMAIL]: new EmailNotificationAdapter(),
    [NOTIFICATION_CHANNELS.FCM]: new FcmNotificationAdapter(),
  };
}

module.exports = {
  InAppNotificationAdapter,
  EmailNotificationAdapter,
  FcmNotificationAdapter,
  createDeliveryAdapters,
};

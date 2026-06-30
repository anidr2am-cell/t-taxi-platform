const DELIVERY_STATUS = require('../constants/notificationDeliveryStatus');
const NOTIFICATION_CHANNELS = require('../constants/notificationChannels');
const config = require('../config/env');
const fs = require('node:fs');

const CONFIG_MISSING = 'CONFIG_MISSING';
const INVALID_RECIPIENT = 'PERMANENT_INVALID_RECIPIENT';
const FCM_TOKEN_MISSING = 'CONFIG_MISSING_FCM_TOKEN';
const FCM_INVALID_TOKEN = 'PERMANENT_FCM_INVALID_TOKEN';

class InAppNotificationAdapter {
  async send(_notification, _recipient) {
    return { status: DELIVERY_STATUS.DELIVERED };
  }
}

class EmailNotificationAdapter {
  constructor(options = {}) {
    this.smtp = options.smtp ?? config.smtp;
    this.transportFactory = options.transportFactory;
    this.transport = options.transport ?? null;
  }

  isConfigured() {
    const smtp = this.smtp;
    return Boolean(smtp.host && (smtp.fromEmail || smtp.from));
  }

  normalizeFrom() {
    const from = this.smtp.fromEmail || this.smtp.from;
    if (!from) return null;
    return this.smtp.fromName ? `"${this.smtp.fromName}" <${from}>` : from;
  }

  getRecipientEmail(notification) {
    const email = notification.recipient_email;
    if (!email || typeof email !== 'string') return null;
    const normalized = email.trim();
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalized) ? normalized : null;
  }

  buildMessage(notification) {
    const bookingNumber = notification.booking_number
      || notification.payload?.bookingNumber
      || 'your booking';
    const locale = String(notification.recipient_locale || notification.payload?.locale || '').toLowerCase();
    const isKorean = locale.startsWith('ko');
    const pickup = notification.scheduled_pickup_at
      ? `${isKorean ? '픽업' : 'Pickup'}: ${notification.scheduled_pickup_at}`
      : null;
    const route = [notification.origin_address, notification.destination_address]
      .filter(Boolean)
      .join(' to ');
    const status = notification.booking_status
      ? `${isKorean ? '현재 상태' : 'Current status'}: ${notification.booking_status}`
      : null;
    const lines = [
      notification.body,
      '',
      `${isKorean ? '예약번호' : 'Booking'}: ${bookingNumber}`,
      pickup,
      route ? `${isKorean ? '경로' : 'Route'}: ${route}` : null,
      status,
      '',
      isKorean
        ? 'TTaxi에서 예약번호와 전화번호로 예약 상태를 확인할 수 있습니다.'
        : 'You can check your booking status in TTaxi with your booking number and phone number.',
    ].filter((line) => line != null);

    return {
      subject: notification.title,
      text: lines.join('\n'),
    };
  }

  async createTransport() {
    if (this.transport) return this.transport;
    if (this.transportFactory) {
      this.transport = this.transportFactory({
        host: this.smtp.host,
        port: this.smtp.port,
        secure: Boolean(this.smtp.secure),
        auth: this.smtp.user ? {
          user: this.smtp.user,
          pass: this.smtp.password,
        } : undefined,
      });
      return this.transport;
    }

    // Loaded lazily so tests and unconfigured local development do not need SMTP setup.
    // eslint-disable-next-line global-require
    const nodemailer = require('nodemailer');
    this.transport = nodemailer.createTransport({
      host: this.smtp.host,
      port: this.smtp.port,
      secure: Boolean(this.smtp.secure),
      auth: this.smtp.user ? {
        user: this.smtp.user,
        pass: this.smtp.password,
      } : undefined,
    });
    return this.transport;
  }

  isPermanentSmtpError(err) {
    const code = String(err?.code || err?.responseCode || '');
    const message = String(err?.message || '').toLowerCase();
    return code === '550'
      || code === '553'
      || message.includes('invalid recipient')
      || message.includes('recipient address rejected');
  }

  async send(notification, _recipient) {
    if (!this.isConfigured()) {
      return { status: DELIVERY_STATUS.SKIPPED, error: CONFIG_MISSING };
    }

    const to = this.getRecipientEmail(notification);
    if (!to) {
      return { status: DELIVERY_STATUS.FAILED, error: INVALID_RECIPIENT, permanent: true };
    }

    try {
      const transport = await this.createTransport();
      await transport.sendMail({
        from: this.normalizeFrom(),
        to,
        ...this.buildMessage(notification),
      });
      return { status: DELIVERY_STATUS.DELIVERED };
    } catch (err) {
      if (this.isPermanentSmtpError(err)) {
        return { status: DELIVERY_STATUS.FAILED, error: INVALID_RECIPIENT, permanent: true };
      }
      throw err;
    }
  }
}

class FcmNotificationAdapter {
  constructor(options = {}) {
    this.firebase = options.firebase ?? config.firebase;
    this.admin = options.admin ?? null;
    this.app = null;
  }

  isConfigured() {
    const fb = this.firebase;
    return Boolean(
      fb.projectId && (fb.clientEmail || fb.serviceAccountPath),
    );
  }

  buildMessage(notification) {
    return {
      notification: {
        title: notification.title,
        body: notification.body,
      },
      data: {
        notificationId: String(notification.id),
        notificationType: notification.type,
        bookingNumber: String(notification.booking_number || notification.payload?.bookingNumber || ''),
      },
    };
  }

  getToken(notification) {
    const token = notification.fcm_token ?? notification.fcmToken;
    return typeof token === 'string' && token.trim()
      ? token.trim()
      : null;
  }

  isInvalidTokenError(err) {
    const code = String(err?.code || err?.errorInfo?.code || '');
    const message = String(err?.message || '').toLowerCase();
    return code === 'messaging/registration-token-not-registered'
      || code === 'messaging/invalid-registration-token'
      || code === 'messaging/invalid-argument'
      || message.includes('registration token is not a valid')
      || message.includes('requested entity was not found');
  }

  async getAdmin() {
    if (this.admin) return this.admin;
    // eslint-disable-next-line global-require
    this.admin = require('firebase-admin');
    return this.admin;
  }

  buildFirebaseCredential(admin) {
    if (this.firebase.serviceAccountPath) {
      const raw = fs.readFileSync(this.firebase.serviceAccountPath, 'utf8');
      return admin.credential.cert(JSON.parse(raw));
    }
    if (this.firebase.clientEmail && this.firebase.privateKey) {
      return admin.credential.cert({
        projectId: this.firebase.projectId,
        clientEmail: this.firebase.clientEmail,
        privateKey: this.firebase.privateKey.replace(/\\n/g, '\n'),
      });
    }
    return null;
  }

  async send(notification, _recipient) {
    if (!this.isConfigured()) {
      return { status: DELIVERY_STATUS.SKIPPED, error: CONFIG_MISSING };
    }

    const token = this.getToken(notification);
    if (!token) {
      return { status: DELIVERY_STATUS.SKIPPED, error: FCM_TOKEN_MISSING };
    }

    const admin = await this.getAdmin();
    if (!admin.apps?.length) {
      const credential = this.buildFirebaseCredential(admin);
      admin.initializeApp(credential ? {
        credential,
        projectId: this.firebase.projectId,
      } : {
        projectId: this.firebase.projectId,
      });
    }

    try {
      await admin.messaging().send({
        token,
        ...this.buildMessage(notification),
      });
      return { status: DELIVERY_STATUS.DELIVERED };
    } catch (err) {
      if (this.isInvalidTokenError(err)) {
        return { status: DELIVERY_STATUS.FAILED, error: FCM_INVALID_TOKEN, permanent: true };
      }
      throw err;
    }
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
  FCM_INVALID_TOKEN,
};

/**
 * config/firebase.js — Firebase Admin SDK (FCM push notifications)
 *
 * credentials 없으면 null 반환 — 개발 중 푸시 없이 서버 실행 가능
 */
const path = require('path');
const env = require('./env');
const logger = require('../utils/logger');

let firebaseApp = null;

function initFirebase() {
  if (firebaseApp) return firebaseApp;

  const fb = env.firebase;

  try {
    const admin = require('firebase-admin');

    if (fb.serviceAccountPath) {
      const serviceAccount = require(path.resolve(fb.serviceAccountPath));
      firebaseApp = admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
      });
    } else if (fb.projectId && fb.clientEmail && fb.privateKey) {
      firebaseApp = admin.initializeApp({
        credential: admin.credential.cert({
          projectId: fb.projectId,
          clientEmail: fb.clientEmail,
          privateKey: fb.privateKey.replace(/\\n/g, '\n'),
        }),
      });
    } else {
      logger.warn('Firebase not configured — push notifications disabled');
      return null;
    }

    logger.info('Firebase Admin initialized');
    return firebaseApp;
  } catch (err) {
    logger.warn('Firebase init skipped', { message: err.message });
    return null;
  }
}

module.exports = {
  initFirebase,
  getFirebaseApp: () => firebaseApp || initFirebase(),
};

/**
 * config/index.js — Central configuration hub
 *
 * 모든 config/*.js를 하나로 모아 export합니다.
 * 다른 파일에서는 process.env를 직접 읽지 않고 config를 사용하세요.
 */
const env = require('./env');

module.exports = {
  server: env.server,
  jwt: env.jwt,
  external: env.external,
  upload: env.upload,
  logging: env.logging,
  database: require('./database'),
  firebase: require('./firebase'),
  swagger: require('./swagger'),
  multer: require('./multer'),
  cors: require('./cors'),
  socket: require('./socket'),
};

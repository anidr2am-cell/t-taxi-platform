/**
 * utils/logger.js — Winston structured logging
 *
 * 사용: const logger = require('./utils/logger');
 *       logger.info('message', { meta });
 *
 * production: JSON logs → log aggregation (Datadog, CloudWatch 등)
 * development: colorized console
 */
const path = require('path');
const fs = require('fs');
const winston = require('winston');
const env = require('../config/env');

const logDir = path.resolve(process.cwd(), env.logging.dir);

if (!fs.existsSync(logDir)) {
  fs.mkdirSync(logDir, { recursive: true });
}

const { combine, timestamp, json, errors, printf, colorize } = winston.format;

const devFormat = printf(({ level, message, timestamp: ts, ...meta }) => {
  const extra = Object.keys(meta).length ? ` ${JSON.stringify(meta)}` : '';
  return `${ts} [${level}] ${message}${extra}`;
});

const logger = winston.createLogger({
  level: env.logging.level,
  defaultMeta: { service: 'ttaxi-api' },
  transports: [
    new winston.transports.File({
      filename: path.join(logDir, 'error.log'),
      level: 'error',
      format: combine(timestamp(), errors({ stack: true }), json()),
    }),
    new winston.transports.File({
      filename: path.join(logDir, 'combined.log'),
      format: combine(timestamp(), errors({ stack: true }), json()),
    }),
  ],
});

if (env.server.nodeEnv !== 'production') {
  logger.add(
    new winston.transports.Console({
      format: combine(colorize(), timestamp(), errors({ stack: true }), devFormat),
    }),
  );
} else {
  logger.add(
    new winston.transports.Console({
      format: combine(timestamp(), json()),
    }),
  );
}

module.exports = logger;

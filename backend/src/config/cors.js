/**
 * config/cors.js — CORS options for Express & Socket.IO
 */
const env = require('./env');

const raw = env.cors.origin || 'http://localhost:8080';
const origin = raw === '*' ? true : raw.split(',').map((s) => s.trim());

module.exports = {
  origin,
  options: {
    origin,
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
  },
};

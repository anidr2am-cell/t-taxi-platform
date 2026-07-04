const bcrypt = require('bcryptjs');

const BCRYPT_ROUNDS = 12;

function hashPassword(password) {
  return bcrypt.hash(password, BCRYPT_ROUNDS);
}

function verifyPassword(password, passwordHash) {
  return bcrypt.compare(password, passwordHash);
}

module.exports = {
  BCRYPT_ROUNDS,
  hashPassword,
  verifyPassword,
};

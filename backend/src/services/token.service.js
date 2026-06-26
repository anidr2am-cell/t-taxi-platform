const jwt = require('jsonwebtoken');
const { randomUUID } = require('crypto');
const config = require('../config');
const { parseExpiresInToSeconds } = require('../utils/jwtExpires');

class TokenService {
  constructor(revokedRefreshTokenStore) {
    this.revokedRefreshTokenStore = revokedRefreshTokenStore;
    this.accessExpiresIn = config.jwt.accessExpiresIn;
    this.refreshExpiresIn = config.jwt.refreshExpiresIn;
    this.accessExpiresInSeconds = parseExpiresInToSeconds(this.accessExpiresIn);
    this.refreshExpiresInSeconds = parseExpiresInToSeconds(this.refreshExpiresIn);
  }

  signAccessToken(user) {
    return jwt.sign(
      {
        sub: user.id,
        email: user.email,
        role: user.role,
        type: 'access',
      },
      config.jwt.accessSecret,
      { expiresIn: this.accessExpiresIn },
    );
  }

  signRefreshToken(user) {
    const jti = randomUUID();
    const token = jwt.sign(
      {
        sub: user.id,
        type: 'refresh',
        jti,
      },
      config.jwt.refreshSecret,
      { expiresIn: this.refreshExpiresIn },
    );

    return { token, jti };
  }

  verifyAccessToken(token) {
    const payload = jwt.verify(token, config.jwt.accessSecret);
    if (payload.type !== 'access') {
      throw new Error('Invalid token type');
    }
    return {
      id: Number(payload.sub),
      email: payload.email,
      role: payload.role,
    };
  }

  verifyRefreshToken(token) {
    const payload = jwt.verify(token, config.jwt.refreshSecret);
    if (payload.type !== 'refresh' || !payload.jti) {
      throw new Error('Invalid token type');
    }

    if (this.revokedRefreshTokenStore.isRevoked(payload.jti)) {
      throw new Error('Refresh token revoked');
    }

    return {
      userId: Number(payload.sub),
      jti: payload.jti,
      exp: payload.exp,
    };
  }

  revokeRefreshToken(jti, exp) {
    const expiresAtMs = typeof exp === 'number' ? exp * 1000 : Date.now() + this.refreshExpiresInSeconds * 1000;
    this.revokedRefreshTokenStore.revoke(jti, expiresAtMs);
  }

  getAccessExpiresInSeconds() {
    return this.accessExpiresInSeconds;
  }
}

module.exports = TokenService;

class RevokedRefreshTokenStore {
  constructor() {
    this.revoked = new Map();
  }

  revoke(jti, expiresAtMs) {
    if (!jti) return;
    this.revoked.set(jti, expiresAtMs);
    this.cleanup();
  }

  isRevoked(jti) {
    if (!jti) return true;
    const expiresAtMs = this.revoked.get(jti);
    if (!expiresAtMs) return false;
    if (Date.now() >= expiresAtMs) {
      this.revoked.delete(jti);
      return false;
    }
    return true;
  }

  cleanup() {
    const now = Date.now();
    for (const [jti, expiresAtMs] of this.revoked.entries()) {
      if (now >= expiresAtMs) {
        this.revoked.delete(jti);
      }
    }
  }
}

module.exports = RevokedRefreshTokenStore;

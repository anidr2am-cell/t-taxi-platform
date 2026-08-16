function attachTransactionMethods(conn) {
  let inTransaction = false;
  conn.beginTransaction = async () => {
    inTransaction = true;
  };
  conn.commit = async () => {
    inTransaction = false;
  };
  conn.rollback = async () => {
    inTransaction = false;
  };
  conn.isInTransaction = () => inTransaction;
  return conn;
}

function createLockState() {
  const held = new Set();
  return {
    held,
    createConn() {
      const state = this;
      return attachTransactionMethods({
        released: false,
        async query(sql, params) {
          if (sql.includes('GET_LOCK')) {
            const name = params[0];
            if (state.held.has(name)) {
              return [[{ acquired: 0 }]];
            }
            state.held.add(name);
            return [[{ acquired: 1 }]];
          }
          if (sql.includes('RELEASE_LOCK')) {
            state.held.delete(params[0]);
            return [[{ released: 1 }]];
          }
          throw new Error(`Unexpected query: ${sql}`);
        },
        release() {
          this.released = true;
        },
      });
    },
  };
}

function createSerializedLockState() {
  let heldName = null;
  return {
    createConn() {
      return attachTransactionMethods({
        released: false,
        async query(sql, params) {
          if (sql.includes('GET_LOCK')) {
            const name = params[0];
            const timeoutMs = Number(params[1]) * 1000;
            const deadline = Date.now() + timeoutMs;
            while (heldName === name) {
              if (Date.now() >= deadline) {
                return [[{ acquired: 0 }]];
              }
              await new Promise((resolve) => setTimeout(resolve, 5));
            }
            if (heldName && heldName !== name) {
              return [[{ acquired: 0 }]];
            }
            heldName = name;
            return [[{ acquired: 1 }]];
          }
          if (sql.includes('RELEASE_LOCK')) {
            if (heldName === params[0]) {
              heldName = null;
            }
            return [[{ released: 1 }]];
          }
          throw new Error(`Unexpected query: ${sql}`);
        },
        release() {
          this.released = true;
        },
      });
    },
  };
}

module.exports = {
  createLockState,
  createSerializedLockState,
};

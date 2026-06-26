/**
 * helpers/container.js — Simple Dependency Injection container
 *
 * Service / Repository를 등록하고 Controller에서 가져옵니다.
 *
 * 예 (구현 단계):
 *   container.register('bookingService', () => new BookingService(bookingRepo));
 *   const bookingService = container.get('bookingService');
 */
class Container {
  constructor() {
    this.registry = new Map();
  }

  register(name, factory) {
    this.registry.set(name, { factory, instance: null });
  }

  get(name) {
    const entry = this.registry.get(name);
    if (!entry) {
      throw new Error(`DI: '${name}' is not registered`);
    }
    if (!entry.instance) {
      entry.instance = entry.factory(this);
    }
    return entry.instance;
  }

  clear() {
    this.registry.clear();
  }
}

const container = new Container();

// TODO: register repositories & services when implemented
// container.register('userRepository', (c) => new UserRepository(database.pool));

module.exports = container;

'use strict';

// Flutter generates a root-scoped cache worker by default. T-Rider deliberately
// replaces it after every web build so static routes such as /blog always reach
// nginx instead of receiving a cached Flutter index.html.
self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    await self.registration.unregister();
    const clients = await self.clients.matchAll({ type: 'window' });
    await Promise.all(clients.map((client) => (
      client.url && 'navigate' in client ? client.navigate(client.url) : undefined
    )));
  })());
});

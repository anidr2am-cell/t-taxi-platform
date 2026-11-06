self.addEventListener('push', function(event) {
  var payload = {};
  try {
    payload = event.data ? event.data.json() : {};
  } catch (_) {
    payload = {};
  }

  var notification = payload.notification || {};
  var title = notification.title || 'T-Ride';
  var options = {
    body: notification.body || '',
    data: payload.data || {}
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', function(event) {
  if (['CUSTOMER_GATE_ARRIVED', 'CUSTOMER_BOOKING_UPDATED'].indexOf((event.notification.data || {}).notificationType) < 0) return;
  event.notification.close();
  event.waitUntil(clients.matchAll({type:'window', includeUncontrolled:true}).then(function(windows) {
    var target = new URL('/driver', self.location.origin).href;
    var existing = windows.find(function(w) { return w.url.indexOf(target) === 0; });
    return existing ? existing.focus() : clients.openWindow(target);
  }));
});

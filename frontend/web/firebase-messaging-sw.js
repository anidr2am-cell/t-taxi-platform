self.addEventListener('push', function(event) {
  var payload = {};
  try {
    payload = event.data ? event.data.json() : {};
  } catch (_) {
    payload = {};
  }

  var notification = payload.notification || {};
  var title = notification.title || 'TTaxi';
  var options = {
    body: notification.body || '',
    data: payload.data || {}
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

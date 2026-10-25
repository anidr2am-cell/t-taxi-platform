'use strict';
// Shared by the static landing and blog. Never stores marketing data before consent.
(() => {
  const consentKey = 'tride_analytics_consent';
  const keys = ['tride_marketing_first_touch', 'tride_marketing_last_touch'];
  const fields = ['source', 'medium', 'campaign', 'content', 'term'];
  const ttl = 90 * 86400000;
  const read = key => { try { return localStorage.getItem(key); } catch { return null; } };
  const remove = key => { try { localStorage.removeItem(key); } catch {} };
  const valid = value => typeof value === 'string' && /^[a-zA-Z0-9._-]{1,150}$/.test(value)
    && !/^\+?[0-9\s()-]{7,20}$/.test(value) ? value : null;
  const customerPath = path => /^\/(?:$|(?:en|th|ja|zh)\/?$|booking\/?$|blog(?:\/|$))/.test(path);
  function stored(key) {
    try {
      const touch = JSON.parse(read(key));
      if (!touch || !Number.isFinite(Date.parse(touch.expires_at)) || Date.parse(touch.expires_at) <= Date.now()
          || !customerPath(touch.landing_page || '')) { remove(key); return null; }
      return touch;
    } catch { remove(key); return null; }
  }
  function incoming() {
    const params = new URLSearchParams(location.search), touch = {};
    for (const field of fields) { const value = valid(params.get('utm_' + field)); if (value) touch[field] = value; }
    return touch;
  }
  function capture() {
    if (read(consentKey) === 'denied') { keys.forEach(remove); return; }
    if (read(consentKey) !== 'granted' || !customerPath(location.pathname)) return;
    const now = Date.now(), touch = {schema_version: 2, ...incoming(), landing_page: location.pathname,
      captured_at: new Date(now).toISOString(), expires_at: new Date(now + ttl).toISOString()};
    let internal = false;
    try {
      const ref = new URL(document.referrer);
      internal = ref.origin === location.origin;
      if (!internal && /^[a-z0-9.-]{1,255}$/.test(ref.hostname)
          && !['kauth.kakao.com', 'access.line.me', 'accounts.google.com'].includes(ref.hostname)) touch.referrer_host = ref.hostname;
    } catch {}
    try {
      const first = stored(keys[0]), last = stored(keys[1]);
      if (!first) localStorage.setItem(keys[0], JSON.stringify(touch));
      // Same-site article/locale navigation must not replace an external campaign.
      if (fields.some(f => touch[f]) && (!internal || !last)) localStorage.setItem(keys[1], JSON.stringify(touch));
    } catch {}
  }
  function decorateUrl(raw) {
    const url = new URL(raw, location.href);
    if (url.origin !== location.origin || !customerPath(url.pathname)) return url.href;
    if (read(consentKey) === 'denied') {
      fields.forEach(f => url.searchParams.delete('utm_' + f));
    } else if (read(consentKey) !== 'granted') {
      // Carry only allowlisted campaign labels through navigation; no storage or network tracking.
      for (const [field, value] of Object.entries(incoming())) url.searchParams.set('utm_' + field, value);
    }
    return url.href;
  }
  function campaignParams() {
    if (read(consentKey) !== 'granted') return {};
    const touch = stored(keys[1]) || stored(keys[0]) || {};
    const names = {source:'campaign_source', medium:'campaign_medium', campaign:'campaign_name', content:'campaign_content', term:'campaign_term'};
    return Object.fromEntries(fields.filter(f => valid(touch[f])).map(f => [names[f], touch[f]]));
  }
  window.trideMarketing = {capture, decorateUrl, campaignParams};
  capture();
  function decorateLinks() {
    document.querySelectorAll('a[href]').forEach(a => {
      try { a.href = decorateUrl(a.href); } catch {}
    });
  }
  decorateLinks();
  // Refresh after consent changes and support dynamically inserted customer links.
  document.addEventListener('click', event => {
    const a = event.target.closest('a[href]');
    if (a) { try { a.href = decorateUrl(a.href); } catch {} }
  }, true);
})();

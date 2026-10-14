'use strict';
// Test fixture only: reproduces a legacy root-scoped Flutter navigation cache.
const CACHE='flutter-app-cache';
self.addEventListener('install',e=>e.waitUntil((async()=>{const r=await fetch('/index.html',{cache:'reload'});await(await caches.open(CACHE)).put('/',r);await self.skipWaiting();})()));
self.addEventListener('activate',e=>e.waitUntil(self.clients.claim()));
self.addEventListener('fetch',e=>{const u=new URL(e.request.url);if(e.request.mode==='navigate'&&u.pathname==='/')e.respondWith(caches.open(CACHE).then(c=>c.match('/')));});

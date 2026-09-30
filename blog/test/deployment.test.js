import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (relative) => fs.readFileSync(path.join(root, relative), 'utf8');

test('frontend image builds blog separately and preserves reservation backend isolation', () => {
  const dockerfile = read('deploy/docker/Dockerfile.frontend');
  assert.match(dockerfile, /FROM node:22-alpine AS blog-build/);
  assert.match(dockerfile, /npm run blog:build/);
  assert.match(dockerfile, /COPY --from=blog-build \/app\/blog\/dist \/usr\/share\/nginx\/html\/blog/);
  assert.match(dockerfile, /cp \/tmp\/flutter_service_worker_cleanup\.js build\/web\/flutter_service_worker\.js/);
  assert.doesNotMatch(dockerfile, /Dockerfile\.backend/);
});

test('nginx serves blog before SPA fallback with separate cache policies', () => {
  for (const file of ['deploy/docker/nginx.frontend.conf', 'deploy/docker/nginx.frontend.production.conf']) {
    const nginx = read(file);
    const blogLocation = nginx.indexOf('location /blog/');
    const spaFallback = nginx.indexOf('try_files $uri $uri/ /index.html');
    assert.ok(blogLocation >= 0 && blogLocation < spaFallback, `${file}: blog route must precede SPA fallback`);
    assert.match(nginx, /location \/blog\/ \{[\s\S]*?Cache-Control "no-cache"[\s\S]*?try_files \$uri \$uri\/ =404;/);
    assert.match(nginx, /location ~\* \^\/blog\/assets\/[\s\S]*?max-age=2592000/);
    assert.match(nginx, /location = \/sitemap-blog\.xml/);
  }
});

test('cleanup worker unregisters root Flutter worker without caching requests', () => {
  const worker = read('deploy/docker/flutter_service_worker_cleanup.js');
  assert.match(worker, /registration\.unregister\(\)/);
  assert.match(worker, /skipWaiting\(\)/);
  assert.doesNotMatch(worker, /addEventListener\(['"]fetch/);
  assert.doesNotMatch(worker, /caches\.open/);
});

test('sitemap index and robots expose app and blog sitemaps', () => {
  const index = read('frontend/web/sitemap.xml');
  const robots = read('frontend/web/robots.txt');
  assert.match(index, /<sitemapindex/);
  assert.match(index, /sitemap-app\.xml/);
  assert.match(index, /sitemap-blog\.xml/);
  assert.match(robots, /Sitemap: https:\/\/trider\.taxi\/sitemap-blog\.xml/);
});

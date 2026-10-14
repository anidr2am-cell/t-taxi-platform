import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {execFileSync} from 'node:child_process';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
test('root sitemap discovers all landing languages and the independently built blog',()=>{
 execFileSync(process.execPath,['landing/build.cjs'],{cwd:root});
 const read=name=>fs.readFileSync(path.join(root,'landing/dist',name),'utf8');
 const index=read('sitemap.xml');
 assert.match(index,/<sitemapindex /);
 assert.deepEqual([...index.matchAll(/<loc>([^<]+)<\/loc>/g)].map(m=>m[1]),['https://trider.taxi/sitemap-landing.xml','https://trider.taxi/sitemap-blog.xml']);
 const landing=read('sitemap-landing.xml');
 const urls=[...landing.matchAll(/<url>(.*?)<\/url>/g)].map(m=>m[1]);
 assert.equal(urls.length,5);
 for(const item of urls){assert.match(item,/<lastmod>\d{4}-\d{2}-\d{2}<\/lastmod>/);for(const lang of ['ko','en','th','ja','zh','x-default'])assert.ok(item.includes(`hreflang="${lang}"`));}
 assert.match(read('robots.txt'),/Sitemap: https:\/\/trider\.taxi\/sitemap.xml/);
 const docker=fs.readFileSync(path.join(root,'deploy/docker/Dockerfile.frontend'),'utf8');
 for(const name of ['sitemap.xml','sitemap-landing.xml','sitemap-blog.xml'])assert.ok(docker.includes(`/usr/share/nginx/html/${name}`));
});

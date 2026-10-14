// Assemble separate landing + existing Flutter + blog without overwriting Flutter index.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=__dirname,repo=path.dirname(root),flutter=path.join(repo,'frontend/build/web'),blog=path.join(repo,'blog/dist');
const source=fs.readFileSync(path.join(flutter,'index.html'));if(!source.toString().includes('flutter_bootstrap.js'))throw Error('Expected an existing Flutter build');
const target=fs.mkdtempSync(path.join(root,'preview-build-'));
fs.cpSync(flutter,target,{recursive:true});fs.cpSync(path.join(root,'dist'),path.join(target,'landing'),{recursive:true});
fs.cpSync(path.join(root,'dist/landing-assets'),path.join(target,'landing-assets'),{recursive:true});for(const name of ['sitemap.xml','robots.txt'])fs.copyFileSync(path.join(root,'dist',name),path.join(target,name));fs.cpSync(blog,path.join(target,'blog'),{recursive:true});fs.copyFileSync(path.join(blog,'sitemap-blog.xml'),path.join(target,'sitemap-blog.xml'));
fs.copyFileSync(path.join(repo,'deploy/docker/flutter_service_worker_cleanup.js'),path.join(target,'flutter_service_worker.js'));
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');if(hash(fs.readFileSync(path.join(target,'index.html')))!==hash(source))throw Error('Flutter index was altered');
console.log(JSON.stringify({target,flutterIndexUnchanged:true,flutterIndexSha256:hash(source)}));

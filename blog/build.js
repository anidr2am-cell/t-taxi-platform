import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import matter from 'gray-matter';
import { marked } from 'marked';

const BLOG_ORIGIN = 'https://trider.taxi';
const AUTHOR = 'TRider';
const CATEGORIES = ['airport', 'golf', 'travel', 'faq'];
const LANGUAGES = ['ko', 'en', 'ja', 'zh', 'th'];
const here = path.dirname(fileURLToPath(import.meta.url));
const postsDir = path.join(here, 'posts');
const distDir = path.join(here, 'dist');

const escapeHtml = (value = '') => String(value)
  .replaceAll('&', '&amp;')
  .replaceAll('<', '&lt;')
  .replaceAll('>', '&gt;')
  .replaceAll('"', '&quot;')
  .replaceAll("'", '&#39;');

const escapeJson = (value) => JSON.stringify(value).replaceAll('<', '\\u003c');
const asDate = (value, key, file) => {
  const raw = value instanceof Date ? value.toISOString().slice(0, 10) : String(value || '');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(raw)) throw new Error(`${file}: ${key} must be YYYY-MM-DD`);
  return raw;
};

function validatePost(data, file) {
  for (const key of ['title', 'description', 'slug', 'lang', 'category', 'date', 'updated']) {
    if (!data[key]) throw new Error(`${file}: missing frontmatter field ${key}`);
  }
  if (String(data.description).length > 160) throw new Error(`${file}: description must be 160 characters or fewer`);
  if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(data.slug)) throw new Error(`${file}: invalid slug`);
  if (!LANGUAGES.includes(data.lang)) throw new Error(`${file}: unsupported lang ${data.lang}`);
  if (!CATEGORIES.includes(data.category)) throw new Error(`${file}: unsupported category ${data.category}`);
  if (data.cover && (!data.coverWidth || !data.coverHeight)) {
    throw new Error(`${file}: coverWidth and coverHeight are required with cover`);
  }
}

const renderer = new marked.Renderer();
renderer.image = ({ href, title, text }) => {
  const titleAttr = title ? ` title="${escapeHtml(title)}"` : '';
  return `<img src="${escapeHtml(href)}" alt="${escapeHtml(text)}" loading="lazy" decoding="async" width="1200" height="675"${titleAttr}>`;
};
marked.use({ renderer, gfm: true });

function readPosts() {
  const slugs = new Set();
  return fs.readdirSync(postsDir)
    .filter((name) => name.endsWith('.md'))
    .map((name) => {
      const file = path.join(postsDir, name);
      const parsed = matter(fs.readFileSync(file, 'utf8'));
      validatePost(parsed.data, name);
      if (slugs.has(parsed.data.slug)) throw new Error(`${name}: duplicate slug ${parsed.data.slug}`);
      slugs.add(parsed.data.slug);
      return {
        ...parsed.data,
        date: asDate(parsed.data.date, 'date', name),
        updated: asDate(parsed.data.updated, 'updated', name),
        content: parsed.content,
      };
    })
    .sort((a, b) => b.date.localeCompare(a.date));
}

function page({ title, description, canonical, lang = 'ko', body, image, jsonLd = [] }) {
  const ogImage = image ? new URL(image, BLOG_ORIGIN).href : `${BLOG_ORIGIN}/icons/Icon-512.png`;
  return `<!doctype html>
<html lang="${escapeHtml(lang)}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>${escapeHtml(title)}</title>
  <meta name="description" content="${escapeHtml(description)}">
  <link rel="canonical" href="${escapeHtml(canonical)}">
  <meta property="og:type" content="article">
  <meta property="og:site_name" content="TRider">
  <meta property="og:title" content="${escapeHtml(title)}">
  <meta property="og:description" content="${escapeHtml(description)}">
  <meta property="og:image" content="${escapeHtml(ogImage)}">
  <meta property="og:url" content="${escapeHtml(canonical)}">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${escapeHtml(title)}">
  <meta name="twitter:description" content="${escapeHtml(description)}">
  <meta name="twitter:image" content="${escapeHtml(ogImage)}">
  <link rel="icon" href="/favicon.png">
  <link rel="stylesheet" href="/blog/assets/blog.css">
  ${jsonLd.map((item) => `<script type="application/ld+json">${escapeJson(item)}</script>`).join('\n  ')}
</head>
<body>
  <header class="site-header"><div class="header-inner"><a class="brand" href="/blog/">TRider</a><a class="book-button" href="https://trider.taxi/">예약하기</a></div></header>
  ${body}
  <footer>© TRider · Thailand transfer guide</footer>
</body>
</html>\n`;
}

function postCard(post) {
  return `<article class="post-card"><p class="eyebrow">${escapeHtml(post.category)}</p><h2><a href="/blog/${escapeHtml(post.slug)}">${escapeHtml(post.title)}</a></h2><p>${escapeHtml(post.description)}</p><time datetime="${post.updated}">${post.updated}</time></article>`;
}

function write(relative, content) {
  const target = path.join(distDir, relative);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, content);
}

function build() {
  const posts = readPosts();
  fs.rmSync(distDir, { recursive: true, force: true });
  fs.mkdirSync(distDir, { recursive: true });
  fs.cpSync(path.join(here, 'assets'), path.join(distDir, 'assets'), { recursive: true });

  for (const post of posts) {
    const canonical = `${BLOG_ORIGIN}/blog/${post.slug}`;
    const article = {
      '@context': 'https://schema.org', '@type': 'Article',
      headline: post.title, description: post.description, datePublished: post.date,
      dateModified: post.updated, author: { '@type': 'Organization', name: AUTHOR },
      publisher: { '@type': 'Organization', name: AUTHOR }, mainEntityOfPage: canonical,
      ...(post.cover ? { image: new URL(post.cover, BLOG_ORIGIN).href } : {}),
    };
    const jsonLd = [article];
    if (post.category === 'faq' && Array.isArray(post.faq)) {
      jsonLd.push({
        '@context': 'https://schema.org', '@type': 'FAQPage',
        mainEntity: post.faq.map(({ question, answer }) => ({
          '@type': 'Question', name: question,
          acceptedAnswer: { '@type': 'Answer', text: answer },
        })),
      });
    }
    const cover = post.cover
      ? `<img class="cover" src="${escapeHtml(post.cover)}" alt="" loading="lazy" decoding="async" width="${Number(post.coverWidth)}" height="${Number(post.coverHeight)}">`
      : '';
    const body = `<main><article class="article"><nav><a href="/blog/">블로그</a> / <a href="/blog/category/${post.category}/">${post.category}</a></nav><h1>${escapeHtml(post.title)}</h1><p class="updated">최종 업데이트: <time datetime="${post.updated}">${post.updated}</time></p>${cover}<div class="content">${marked.parse(post.content)}</div><aside class="cta"><strong>✈️ 정찰제 공항픽업 · 24시간 예약</strong><div><a class="cta-primary" href="https://trider.taxi/">지금 예약하기</a><a class="cta-secondary" href="https://open.kakao.com/o/suG4krMi" rel="noopener noreferrer">카카오톡 상담</a></div></aside></article></main>`;
    write(path.join(post.slug, 'index.html'), page({
      title: `${post.title} | TRider`, description: post.description,
      canonical, lang: post.lang, body, image: post.cover, jsonLd,
    }));
  }

  const listBody = `<main><section class="hero"><p class="eyebrow">Thailand travel guide</p><h1>TRider 블로그</h1><p>태국 공항 이동과 여행에 필요한 정보를 확인하세요.</p></section><section class="post-list">${posts.map(postCard).join('')}</section></main>`;
  write('index.html', page({ title: 'TRider 블로그 | 태국 공항 픽업·여행 정보', description: '태국 공항 픽업, 골프 이동, 여행과 예약에 필요한 정보를 전하는 TRider 블로그입니다.', canonical: `${BLOG_ORIGIN}/blog/`, body: listBody }));

  for (const category of CATEGORIES) {
    const categoryPosts = posts.filter((post) => post.category === category);
    const body = `<main><section class="hero"><p class="eyebrow">Category</p><h1>${escapeHtml(category)}</h1></section><section class="post-list">${categoryPosts.length ? categoryPosts.map(postCard).join('') : '<p>등록된 글이 없습니다.</p>'}</section></main>`;
    write(path.join('category', category, 'index.html'), page({ title: `${category} | TRider 블로그`, description: `TRider의 ${category} 관련 여행 정보입니다.`, canonical: `${BLOG_ORIGIN}/blog/category/${category}/`, body }));
  }

  const urls = [`${BLOG_ORIGIN}/blog/`, ...CATEGORIES.map((c) => `${BLOG_ORIGIN}/blog/category/${c}/`), ...posts.map((p) => `${BLOG_ORIGIN}/blog/${p.slug}`)];
  write('sitemap-blog.xml', `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls.map((url) => `  <url><loc>${url}</loc></url>`).join('\n')}\n</urlset>\n`);
  console.log(`Built ${posts.length} blog post(s) in ${distDir}`);
}

build();

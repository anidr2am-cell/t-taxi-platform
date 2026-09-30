import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import matter from 'gray-matter';
import { marked } from 'marked';

const BLOG_ORIGIN = 'https://trider.taxi';
const AUTHOR = 'TRider';
const CATEGORIES = ['airport', 'golf', 'travel', 'faq'];
const LANGUAGES = ['ko', 'en', 'ja', 'zh', 'th'];
const HREFLANG = { ko: 'ko', en: 'en', ja: 'ja', zh: 'zh-Hans', th: 'th' };
const DEFAULT_OG_IMAGE = `${BLOG_ORIGIN}/blog/assets/og-default.png`;
const UI = {
  ko: { blog: '블로그', title: 'TRider 블로그', intro: '태국 공항 이동과 여행에 필요한 정보를 확인하세요.', updated: '최종 업데이트', related: '관련 글', categories: '카테고리', all: '전체', cta: '✈️ 정찰제 공항픽업 · 24시간 예약', book: '지금 예약하기', support: '카카오톡 상담', supportUrl: 'https://open.kakao.com/o/suG4krMi' },
  en: { blog: 'Blog', title: 'TRider Blog', intro: 'Practical guides for airport transfers and travel in Thailand.', updated: 'Last updated', related: 'Related articles', categories: 'Categories', all: 'All posts', cta: '✈️ Fixed-price airport transfers · Book 24/7', book: 'Book now', support: 'WhatsApp', supportUrl: 'https://wa.me/66815693445' },
  ja: { blog: 'ブログ', title: 'TRiderブログ', intro: 'タイの空港送迎と旅行に役立つ情報をご案内します。', updated: '最終更新', related: '関連記事', categories: 'カテゴリー', all: 'すべての記事', cta: '✈️ 定額の空港送迎・24時間予約', book: '今すぐ予約', support: 'LINEで相談', supportUrl: 'https://lin.ee/55A9phq' },
  zh: { blog: '博客', title: 'TRider博客', intro: '查看泰国机场接送和旅行实用信息。', updated: '最后更新', related: '相关文章', categories: '分类', all: '全部文章', cta: '✈️ 固定价格机场接送 · 24小时预约', book: '立即预约', support: 'WhatsApp咨询', supportUrl: 'https://wa.me/66815693445' },
  th: { blog: 'บล็อก', title: 'บล็อก TRider', intro: 'ข้อมูลการเดินทางและบริการรับส่งสนามบินในประเทศไทย', updated: 'อัปเดตล่าสุด', related: 'บทความที่เกี่ยวข้อง', categories: 'หมวดหมู่', all: 'บทความทั้งหมด', cta: '✈️ รถรับส่งสนามบินราคาเหมาจ่าย · จองได้ 24 ชั่วโมง', book: 'จองเลย', support: 'WhatsApp', supportUrl: 'https://wa.me/66815693445' },
};
const CATEGORY_LABELS = {
  ko: { airport: '공항', golf: '골프', travel: '여행', faq: '자주 묻는 질문' },
  en: { airport: 'Airport', golf: 'Golf', travel: 'Travel', faq: 'FAQ' },
  ja: { airport: '空港', golf: 'ゴルフ', travel: '旅行', faq: 'よくある質問' },
  zh: { airport: '机场', golf: '高尔夫', travel: '旅行', faq: '常见问题' },
  th: { airport: 'สนามบิน', golf: 'กอล์ฟ', travel: 'ท่องเที่ยว', faq: 'คำถามที่พบบ่อย' },
};
const here = path.dirname(fileURLToPath(import.meta.url));
const postsDir = process.env.BLOG_POSTS_DIR ? path.resolve(process.env.BLOG_POSTS_DIR) : path.join(here, 'posts');
const distDir = process.env.BLOG_DIST_DIR ? path.resolve(process.env.BLOG_DIST_DIR) : path.join(here, 'dist');

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

function page({ title, description, canonical, lang = 'ko', body, image, jsonLd = [], alternates = '' }) {
  const ogImage = image ? new URL(image, BLOG_ORIGIN).href : DEFAULT_OG_IMAGE;
  return `<!doctype html>
<html lang="${escapeHtml(lang)}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>${escapeHtml(title)}</title>
  <meta name="description" content="${escapeHtml(description)}">
  <link rel="canonical" href="${escapeHtml(canonical)}">
  ${alternates}
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
  <header class="site-header"><div class="header-inner"><a class="brand" href="${listPath(lang)}">TRider</a><a class="book-button" href="https://trider.taxi/">${UI[lang].book}</a></div></header>
  ${body}
  <footer>© TRider · Thailand transfer guide</footer>
</body>
</html>\n`;
}

const postUrl = (post) => `${BLOG_ORIGIN}/blog/${post.slug}`;
const listPath = (lang) => lang === 'ko' ? '/blog/' : `/blog/lang/${lang}/`;
const categoryPath = (lang, category) => lang === 'ko' ? `/blog/category/${category}/` : `/blog/lang/${lang}/category/${category}/`;

function translationAlternates(post, translationGroups) {
  if (!post.translationKey) return [];
  return translationGroups.get(post.translationKey) || [];
}

function alternateLinks(posts) {
  if (posts.length < 2) return '';
  const links = posts.map((item) => `<link rel="alternate" hreflang="${HREFLANG[item.lang]}" href="${postUrl(item)}">`);
  const korean = posts.find((item) => item.lang === 'ko');
  if (korean) links.push(`<link rel="alternate" hreflang="x-default" href="${postUrl(korean)}">`);
  return links.join('\n  ');
}

function languageSwitcher(posts, currentLang) {
  if (posts.length < 2) return '';
  const names = { ko: '한국어', en: 'English', ja: '日本語', zh: '中文', th: 'ไทย' };
  return `<nav class="language-switcher" aria-label="Translations">${posts.map((post) => post.lang === currentLang
    ? `<strong lang="${HREFLANG[post.lang]}">${names[post.lang]}</strong>`
    : `<a lang="${HREFLANG[post.lang]}" hreflang="${HREFLANG[post.lang]}" href="/blog/${post.slug}">${names[post.lang]}</a>`).join('')}</nav>`;
}

function relatedPosts(post, posts) {
  const selected = [];
  const add = (candidate) => {
    if (candidate && candidate.slug !== post.slug && !selected.some((item) => item.slug === candidate.slug)) selected.push(candidate);
  };
  for (const slug of Array.isArray(post.related) ? post.related : []) add(posts.find((item) => item.slug === slug && item.lang === post.lang));
  posts.filter((item) => item.lang === post.lang && item.category === post.category).forEach(add);
  posts.filter((item) => item.lang === post.lang).forEach(add);
  return selected.slice(0, 3);
}

function relatedBlock(post, posts) {
  const related = relatedPosts(post, posts);
  if (!related.length) return '';
  return `<aside class="related"><h2>${UI[post.lang].related}</h2><ul>${related.map((item) => `<li><a href="/blog/${item.slug}">${escapeHtml(item.title)}</a></li>`).join('')}</ul></aside>`;
}

function postCard(post) {
  return `<article class="post-card"><p class="eyebrow">${escapeHtml(CATEGORY_LABELS[post.lang][post.category])}</p><h2><a href="/blog/${escapeHtml(post.slug)}">${escapeHtml(post.title)}</a></h2><p>${escapeHtml(post.description)}</p><p class="updated">${UI[post.lang].updated}: <time datetime="${post.updated}">${post.updated}</time></p></article>`;
}

function write(relative, content) {
  const target = path.join(distDir, relative);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, content);
}

function build() {
  const posts = readPosts();
  const translationGroups = new Map();
  for (const post of posts) {
    if (!post.translationKey) continue;
    const group = translationGroups.get(post.translationKey) || [];
    group.push(post);
    translationGroups.set(post.translationKey, group);
  }
  fs.rmSync(distDir, { recursive: true, force: true });
  fs.mkdirSync(distDir, { recursive: true });
  fs.cpSync(path.join(here, 'assets'), path.join(distDir, 'assets'), { recursive: true });

  for (const post of posts) {
    const canonical = `${BLOG_ORIGIN}/blog/${post.slug}`;
    const translations = translationAlternates(post, translationGroups);
    const ui = UI[post.lang];
    const article = {
      '@context': 'https://schema.org', '@type': 'Article',
      headline: post.title, description: post.description, datePublished: post.date,
      dateModified: post.updated, author: { '@type': 'Organization', name: AUTHOR },
      publisher: { '@type': 'Organization', name: AUTHOR }, mainEntityOfPage: canonical,
      inLanguage: post.lang,
      ...(post.cover ? { image: new URL(post.cover, BLOG_ORIGIN).href } : {}),
    };
    const breadcrumb = {
      '@context': 'https://schema.org', '@type': 'BreadcrumbList',
      itemListElement: [
        { '@type': 'ListItem', position: 1, name: ui.blog, item: `${BLOG_ORIGIN}${listPath(post.lang)}` },
        { '@type': 'ListItem', position: 2, name: CATEGORY_LABELS[post.lang][post.category], item: `${BLOG_ORIGIN}${categoryPath(post.lang, post.category)}` },
        { '@type': 'ListItem', position: 3, name: post.title, item: canonical },
      ],
    };
    const jsonLd = [article, breadcrumb];
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
    const body = `<main><article class="article"><nav><a href="${listPath(post.lang)}">${ui.blog}</a> / <a href="${categoryPath(post.lang, post.category)}">${CATEGORY_LABELS[post.lang][post.category]}</a></nav>${languageSwitcher(translations, post.lang)}<h1>${escapeHtml(post.title)}</h1><p class="updated">${ui.updated}: <time datetime="${post.updated}">${post.updated}</time></p>${cover}<div class="content">${marked.parse(post.content)}</div>${relatedBlock(post, posts)}<aside class="cta"><strong>${ui.cta}</strong><div><a class="cta-primary" href="https://trider.taxi/">${ui.book}</a><a class="cta-secondary" href="${ui.supportUrl}" rel="noopener noreferrer">${ui.support}</a></div></aside></article></main>`;
    write(path.join(post.slug, 'index.html'), page({
      title: `${post.title} | TRider`, description: post.description,
      canonical, lang: post.lang, body, image: post.cover, jsonLd,
      alternates: alternateLinks(translations),
    }));
  }

  for (const lang of LANGUAGES.filter((item) => posts.some((post) => post.lang === item))) {
    const ui = UI[lang];
    const languagePosts = posts.filter((post) => post.lang === lang);
    const filters = LANGUAGES.filter((item) => posts.some((post) => post.lang === item)).map((item) => `<a href="${listPath(item)}" lang="${HREFLANG[item]}">${{ ko: '한국어', en: 'English', ja: '日本語', zh: '中文', th: 'ไทย' }[item]}</a>`).join('');
    const listBody = `<main><section class="hero"><p class="eyebrow">Thailand travel guide</p><h1>${ui.title}</h1><p>${ui.intro}</p><nav class="language-filters" aria-label="Languages">${filters}</nav></section><section class="post-list">${languagePosts.map(postCard).join('')}</section></main>`;
    const listRelative = lang === 'ko' ? 'index.html' : path.join('lang', lang, 'index.html');
    const listCanonical = `${BLOG_ORIGIN}${listPath(lang)}`;
    write(listRelative, page({ title: `${ui.title} | Thailand transfers`, description: ui.intro, canonical: listCanonical, lang, body: listBody }));

    for (const category of CATEGORIES) {
      const categoryPosts = languagePosts.filter((post) => post.category === category);
      const label = CATEGORY_LABELS[lang][category];
      const empty = { ko: '등록된 글이 없습니다.', en: 'No articles yet.', ja: '記事はまだありません。', zh: '暂无文章。', th: 'ยังไม่มีบทความ' }[lang];
      const body = `<main><section class="hero"><p class="eyebrow">${ui.categories}</p><h1>${escapeHtml(label)}</h1><p><a href="${listPath(lang)}">${ui.all}</a></p></section><section class="post-list">${categoryPosts.length ? categoryPosts.map(postCard).join('') : `<p>${empty}</p>`}</section></main>`;
      const relative = lang === 'ko' ? path.join('category', category, 'index.html') : path.join('lang', lang, 'category', category, 'index.html');
      write(relative, page({ title: `${label} | ${ui.title}`, description: `${ui.title} · ${label}`, canonical: `${BLOG_ORIGIN}${categoryPath(lang, category)}`, lang, body }));
    }
  }

  const latestUpdated = posts.reduce((latest, post) => post.updated > latest ? post.updated : latest, '');
  const sitemapEntries = [
    { url: `${BLOG_ORIGIN}/blog/`, lastmod: latestUpdated },
    ...CATEGORIES.map((category) => ({
      url: `${BLOG_ORIGIN}/blog/category/${category}/`,
      lastmod: posts
        .filter((post) => post.category === category)
        .reduce((latest, post) => post.updated > latest ? post.updated : latest, latestUpdated),
    })),
    ...LANGUAGES.filter((lang) => lang !== 'ko' && posts.some((post) => post.lang === lang)).flatMap((lang) => [
      { url: `${BLOG_ORIGIN}${listPath(lang)}`, lastmod: posts.filter((post) => post.lang === lang).reduce((latest, post) => post.updated > latest ? post.updated : latest, '') },
      ...CATEGORIES.map((category) => ({ url: `${BLOG_ORIGIN}${categoryPath(lang, category)}`, lastmod: posts.filter((post) => post.lang === lang && post.category === category).reduce((latest, post) => post.updated > latest ? post.updated : latest, latestUpdated) })),
    ]),
    ...posts.map((post) => ({ url: `${BLOG_ORIGIN}/blog/${post.slug}`, lastmod: post.updated, alternates: translationAlternates(post, translationGroups) })),
  ];
  write('sitemap-blog.xml', `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">\n${sitemapEntries.map(({ url, lastmod, alternates = [] }) => `  <url><loc>${url}</loc><lastmod>${lastmod}</lastmod>${alternates.length > 1 ? alternates.map((item) => `<xhtml:link rel="alternate" hreflang="${HREFLANG[item.lang]}" href="${postUrl(item)}"/>`).join('') + (alternates.some((item) => item.lang === 'ko') ? `<xhtml:link rel="alternate" hreflang="x-default" href="${postUrl(alternates.find((item) => item.lang === 'ko'))}"/>` : '') : ''}</url>`).join('\n')}\n</urlset>\n`);
  console.log(`Built ${posts.length} blog post(s) in ${distDir}`);
}

build();

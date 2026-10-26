// Post sources. Each returns newest-first [{ id, text, url, createdAt }].

const UA = 'tibodog/0.1 (+https://github.com/matthewkim-11/tibodog)';

export class RateLimited extends Error {
  constructor(retryAt) {
    super('rate limited');
    this.retryAt = retryAt;
  }
}

// Network limits: a slow, stuck or huge response can't stall the watcher or fill memory.
const TIMEOUT_MS = 30_000;
const MAX_BYTES = 2 * 1024 * 1024;

async function get(url, headers = {}) {
  return fetch(url, { headers: { 'User-Agent': UA, ...headers }, signal: AbortSignal.timeout(TIMEOUT_MS) });
}

async function readText(res) {
  if (!res.body) return '';
  const reader = res.body.getReader();
  const chunks = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.length;
    if (size > MAX_BYTES) {
      await reader.cancel();
      throw new Error('response too large');
    }
    chunks.push(value);
  }
  return Buffer.concat(chunks).toString('utf8');
}

// Post text ends up in the terminal, notifications and the widget: no control characters (NULs, ANSI
// and OSC escapes), only text.
export const clean = (s) => String(s ?? '').replace(/[\u0000-\u0008\u000b-\u001f\u007f-\u009f]/g, '');

const STATUS = /\/status(?:es)?\/(\d{5,25})(?:\D|$)/;

// The only links tibodog ever opens or hands to the widget: a post on x.com, rebuilt from its id.
// A feed's own <link> could point anywhere (file://, a custom app scheme, a local app).
export function postUrl(username, id) {
  return /^\d{5,25}$/.test(String(id)) ? `https://x.com/${username || 'i'}/status/${id}` : null;
}

export function isPostUrl(url) {
  try {
    const u = new URL(url);
    return u.protocol === 'https:' && /^(www\.|mobile\.)?(x|twitter)\.com$/.test(u.hostname) && STATUS.test(u.pathname);
  } catch {
    return false;
  }
}

// --- X API v2 (needs a bearer token; timeline reads require a paid tier) ---

export function xSource({ username, bearerToken, missingTokenMessage }) {
  if (!bearerToken) throw new Error(missingTokenMessage ?? 'X_BEARER_TOKEN is not set (or use --rss <url>)');
  let userId = null;

  async function api(path) {
    const res = await get(`https://api.x.com/2${path}`, { Authorization: `Bearer ${bearerToken}` });
    if (res.status === 429) {
      const reset = Number(res.headers.get('x-rate-limit-reset'));
      throw new RateLimited(reset ? reset * 1000 : Date.now() + 15 * 60_000);
    }
    const body = await readText(res);
    if (!res.ok) throw new Error(`X API ${res.status}: ${clean(body).slice(0, 200)}`);
    return JSON.parse(body);
  }

  return {
    name: `X API @${username}`,
    async fetch() {
      if (!userId) {
        const { data } = await api(`/users/by/username/${encodeURIComponent(username)}`);
        if (!data) throw new Error(`user @${username} not found`);
        userId = data.id;
      }
      const { data = [] } = await api(
        `/users/${userId}/tweets?max_results=10&exclude=retweets&tweet.fields=created_at,note_tweet`,
      );
      return data.map((t) => ({
        id: String(t.id),
        text: clean(t.note_tweet?.text ?? t.text).trim(),
        url: postUrl(username, t.id),
        createdAt: t.created_at,
      }));
    },
  };
}

// --- RSS / Atom (Nitter, RSSHub, rss.app, ... anything that mirrors the account) ---
// Scanned with indexOf rather than regexes over the whole body, so a malformed or hostile feed stays
// linear time.

const MAX_ITEMS = 50;
const ENTITIES = { lt: '<', gt: '>', quot: '"', apos: "'", amp: '&', nbsp: ' ' };

function unwrapCdata(s) {
  let out = '';
  let i = 0;
  for (;;) {
    const start = s.indexOf('<![CDATA[', i);
    if (start === -1) return out + s.slice(i);
    const end = s.indexOf(']]>', start + 9);
    if (end === -1) return out + s.slice(i, start) + s.slice(start + 9);
    out += s.slice(i, start) + s.slice(start + 9, end);
    i = end + 3;
  }
}

const stripTags = (s) => s.replace(/<[^<>]*>/g, ' ');

const entities = (s) =>
  s.replace(/&(#x[0-9a-f]{1,8}|#\d{1,10}|lt|gt|quot|apos|amp|nbsp);/gi, (_, e) => {
    const name = e.toLowerCase();
    if (name[0] !== '#') return ENTITIES[name];
    const n = name[1] === 'x' ? parseInt(name.slice(2), 16) : Number(name.slice(1));
    return n > 0 && n <= 0x10ffff && (n < 0xd800 || n > 0xdfff) ? String.fromCodePoint(n) : '';
  });

// Escaped HTML in descriptions (&lt;p&gt;) only becomes tags after decoding, so strip twice.
const decode = (s) => clean(stripTags(entities(stripTags(unwrapCdata(s))))).replace(/\s+/g, ' ').trim();

// The first <name ...>...</name> (or a self-closing <name .../>) in xml.
function element(xml, tagName) {
  const name = tagName.toLowerCase(); // pubDate, ...
  const lower = xml.toLowerCase();
  let i = 0;
  while ((i = lower.indexOf(`<${name}`, i)) !== -1) {
    const next = lower[i + name.length + 1];
    if (next === '>' || next === '/' || /\s/.test(next ?? '')) {
      const headEnd = lower.indexOf('>', i);
      if (headEnd === -1) return null;
      const head = xml.slice(i, headEnd + 1);
      if (lower[headEnd - 1] === '/') return { head, inner: '' };
      const close = lower.indexOf(`</${name}`, headEnd);
      if (close === -1) return null;
      return { head, inner: xml.slice(headEnd + 1, close) };
    }
    i += name.length + 1;
  }
  return null;
}

const text = (xml, ...names) => {
  for (const n of names) {
    const el = element(xml, n);
    if (el && el.inner.trim()) return decode(el.inner);
  }
  return '';
};

function items(xml) {
  const lower = xml.toLowerCase();
  const out = [];
  let i = 0;
  while (out.length < MAX_ITEMS) {
    const a = lower.indexOf('<item', i);
    const b = lower.indexOf('<entry', i);
    const start = a === -1 ? b : b === -1 ? a : Math.min(a, b);
    if (start === -1) break;
    const tagName = start === a ? 'item' : 'entry';
    const end = lower.indexOf(`</${tagName}>`, start);
    if (end === -1) break;
    out.push(xml.slice(start, end));
    i = end + tagName.length + 3;
  }
  return out;
}

export function parseFeed(xml, username) {
  return items(xml).map((b) => {
    const linkEl = element(b, 'link');
    const href = linkEl?.head.match(/href\s*=\s*"([^"]*)"/i)?.[1] ?? '';
    const link = (linkEl && decode(linkEl.inner)) || decode(href);
    const guid = text(b, 'guid', 'id');
    const title = text(b, 'title');
    const body = text(b, 'description', 'content', 'summary');
    // Mirrors link to themselves (nitter.net/<user>/status/<id>); the status id is what's shared.
    const sid = link.match(STATUS)?.[1] ?? guid.match(STATUS)?.[1] ?? (/^\d{5,25}$/.test(guid) ? guid : null);
    return {
      id: sid ?? (guid || link),
      text: body.length > title.length ? body : title,
      url: postUrl(username, sid),
      createdAt: text(b, 'pubDate', 'published', 'updated'),
    };
  });
}

export function rssSource({ url, username }) {
  return {
    name: `RSS ${new URL(url).host}`,
    async fetch() {
      const res = await get(url);
      if (res.status === 429) throw new RateLimited(Date.now() + 5 * 60_000);
      if (!res.ok) throw new Error(`RSS ${res.status}`);
      return parseFeed(await readText(res), username);
    },
  };
}

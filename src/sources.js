// Post sources. Each returns newest-first [{ id, text, url, createdAt }].

const UA = 'tibodog/0.1 (+https://github.com/matthewkim-11/tibodog)';

export class RateLimited extends Error {
  constructor(retryAt) {
    super('rate limited');
    this.retryAt = retryAt;
  }
}

// --- X API v2 (needs a bearer token; timeline reads require a paid tier) ---

export function xSource({ username, bearerToken, missingTokenMessage }) {
  if (!bearerToken) throw new Error(missingTokenMessage ?? 'X_BEARER_TOKEN is not set (or use --rss <url>)');
  let userId = null;

  async function api(path) {
    const res = await fetch(`https://api.x.com/2${path}`, {
      headers: { Authorization: `Bearer ${bearerToken}`, 'User-Agent': UA },
    });
    if (res.status === 429) {
      const reset = Number(res.headers.get('x-rate-limit-reset'));
      throw new RateLimited(reset ? reset * 1000 : Date.now() + 15 * 60_000);
    }
    if (!res.ok) throw new Error(`X API ${res.status}: ${(await res.text()).slice(0, 200)}`);
    return res.json();
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
        id: t.id,
        text: t.note_tweet?.text ?? t.text,
        url: `https://x.com/${username}/status/${t.id}`,
        createdAt: t.created_at,
      }));
    },
  };
}

// --- RSS / Atom (Nitter, RSSHub, rss.app, ... anything that mirrors the account) ---

const decode = (s) =>
  s
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;|&apos;/g, "'")
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
    .replace(/&amp;/g, '&')
    .replace(/\s+/g, ' ')
    .trim();

const tag = (xml, name) => {
  const m = xml.match(new RegExp(`<${name}[^>]*>([\\s\\S]*?)</${name}>`, 'i'));
  return m ? m[1] : '';
};

export function parseFeed(xml) {
  const blocks = xml.match(/<(item|entry)[\s>][\s\S]*?<\/\1>/gi) ?? [];
  return blocks.map((b) => {
    const link = decode(tag(b, 'link')) || (b.match(/<link[^>]*href="([^"]+)"/i)?.[1] ?? '');
    const title = decode(tag(b, 'title'));
    const body = decode(tag(b, 'description') || tag(b, 'content') || tag(b, 'summary'));
    return {
      id: decode(tag(b, 'guid') || tag(b, 'id')) || link,
      text: body.length > title.length ? body : title,
      url: link,
      createdAt: decode(tag(b, 'pubDate') || tag(b, 'published') || tag(b, 'updated')),
    };
  });
}

export function rssSource({ url }) {
  return {
    name: `RSS ${new URL(url).host}`,
    async fetch() {
      const res = await fetch(url, { headers: { 'User-Agent': UA } });
      if (res.status === 429) throw new RateLimited(Date.now() + 5 * 60_000);
      if (!res.ok) throw new Error(`RSS ${res.status}`);
      return parseFeed(await res.text());
    },
  };
}

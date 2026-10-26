#!/usr/bin/env node
import { parseArgs } from 'node:util';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { homedir } from 'node:os';
import { join, dirname } from 'node:path';
import { isResetPost } from '../src/detect.js';
import { xSource, rssSource, RateLimited } from '../src/sources.js';
import { playBark, notify, openUrl } from '../src/bark.js';
import { showDog, log, barking, SLEEPING, WATCHING } from '../src/dog.js';
import { detectLang, getMessages } from '../src/i18n.js';
import { showIsland, prepareIsland, islandSupported, writeAlert, isletRunning } from '../src/island.js';

const { values: opt } = parseArgs({
  options: {
    user: { type: 'string', default: process.env.TIBODOG_USER ?? 'thsottiaux' },
    rss: { type: 'string', default: process.env.TIBODOG_RSS },
    interval: { type: 'string', default: process.env.TIBODOG_INTERVAL },
    keyword: { type: 'string', multiple: true, default: [] },
    sound: { type: 'string', default: process.env.TIBODOG_SOUND },
    barks: { type: 'string', default: '1' },
    lang: { type: 'string' },
    open: { type: 'boolean', default: false },
    'no-island': { type: 'boolean', default: false },
    'bark-old': { type: 'boolean', default: false },
    once: { type: 'boolean', default: false },
    test: { type: 'boolean', default: false },
    help: { type: 'boolean', short: 'h', default: false },
  },
});

const lang = detectLang(opt.lang);
const t = getMessages(lang);

if (opt.help) {
  console.log(t.help);
  process.exit(0);
}

const barks = Math.max(1, Number(opt.barks) || 1);
const useIsland = islandSupported() && !opt['no-island'];

function island() {
  return prepareIsland({ onBuild: () => log(t.islandBuilding) }).then((bin) => {
    if (!bin) log(t.islandUnavailable);
    return bin;
  });
}

async function alert(post) {
  showDog(barking(t.bubble));
  log(`🚨 ${post.text}`);
  if (post.url) log(post.url);
  notify(t.notifyTitle, post.text.slice(0, 180));
  if (opt.open && post.url) openUrl(post.url);
  const card = { title: t.islandTitle, body: post.text, url: post.url, woof: t.islandWoof, open: t.islandOpen };
  writeAlert({ id: post.id ?? `test-${Date.now()}`, ...card });
  // Islet barks in its own island; otherwise our own notch dog does.
  if (useIsland && !isletRunning()) {
    await island();
    showIsland({ ...card, lang });
  }
  await playBark(barks, opt.sound);
}

if (opt.test) {
  await alert({ text: t.testPost, url: '' });
  process.exit(0);
}

const statePath = join(homedir(), '.tibodog', `${opt.user}.json`);
const seen = new Set((() => {
  try {
    return JSON.parse(readFileSync(statePath, 'utf8')).seen ?? [];
  } catch {
    return null;
  }
})() ?? []);
const firstRun = seen.size === 0;

function save() {
  mkdirSync(dirname(statePath), { recursive: true });
  writeFileSync(statePath, JSON.stringify({ seen: [...seen].slice(-500) }));
}

let source;
try {
  source = opt.rss
    ? rssSource({ url: opt.rss })
    : xSource({ username: opt.user, bearerToken: process.env.X_BEARER_TOKEN, missingTokenMessage: t.noToken });
} catch (e) {
  showDog(SLEEPING);
  console.error(`🐕 ${e.message}\n   ${t.seeHelp}`);
  process.exit(1);
}

const intervalMs = (Number(opt.interval) || (opt.rss ? 60 : 300)) * 1000;
let primed = !firstRun || opt['bark-old'];

async function tick() {
  const posts = await source.fetch();
  const fresh = posts.filter((p) => p.id && !seen.has(p.id)).reverse(); // oldest first
  let barked = 0;
  for (const p of fresh) {
    seen.add(p.id);
    if (primed && isResetPost(p.text, opt.keyword)) {
      barked++;
      await alert(p);
    }
  }
  if (!primed) log(t.primed(posts.length));
  else if (fresh.length && !barked) log(t.quiet(fresh.length));
  primed = true;
  save();
}

showDog(WATCHING, t.watching(opt.user));
if (useIsland) island(); // build ahead of time so the first reset shows up instantly
log(t.source(source.name, intervalMs / 1000));

while (true) {
  let wait = intervalMs;
  try {
    await tick();
  } catch (e) {
    if (e instanceof RateLimited) {
      wait = Math.max(intervalMs, e.retryAt - Date.now() + 1000);
      log(t.rateLimited(Math.round(wait / 1000)));
    } else {
      log(`⚠️  ${e.message}`);
    }
  }
  if (opt.once) break;
  await new Promise((r) => setTimeout(r, wait));
}

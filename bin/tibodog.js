#!/usr/bin/env node
import { parseArgs } from 'node:util';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { isResetPost } from '../src/detect.js';
import { xSource, rssSource, RateLimited } from '../src/sources.js';
import { playBark, notify, openUrl } from '../src/bark.js';
import { showDog, log, barking, SLEEPING, WATCHING } from '../src/dog.js';
import { detectLang, getMessages } from '../src/i18n.js';
import { ensureWidget, launchWidget, widgetRunning, widgetSupported, installApp, writeAlert, DIR } from '../src/widget.js';

// Anything that slips through still gets logged instead of killing the watcher.
process.on('unhandledRejection', (e) => log(`⚠️  ${e?.message ?? e}`));

const options = {
    user: { type: 'string', default: process.env.TIBODOG_USER ?? 'thsottiaux' },
    rss: { type: 'string', default: process.env.TIBODOG_RSS },
    interval: { type: 'string', default: process.env.TIBODOG_INTERVAL },
    keyword: { type: 'string', multiple: true, default: [] },
    sound: { type: 'string', default: process.env.TIBODOG_SOUND },
    barks: { type: 'string', default: '1' },
    lang: { type: 'string' },
    open: { type: 'boolean', default: false },
    'no-widget': { type: 'boolean', default: false },
    'install-app': { type: 'boolean', default: false },
    'bark-old': { type: 'boolean', default: false },
    once: { type: 'boolean', default: false },
    test: { type: 'boolean', default: false },
    help: { type: 'boolean', short: 'h', default: false },
};

let opt;
try {
  ({ values: opt } = parseArgs({ options }));
} catch (e) {
  const t = getMessages(detectLang());
  console.error(`🐕 ${e.message}\n`);
  console.log(t.help);
  process.exit(2);
}

const lang = detectLang(opt.lang);
const t = getMessages(lang);

if (opt.help) {
  console.log(t.help);
  process.exit(0);
}

// An X handle: also names the state file, so nothing else gets through.
if (!/^[A-Za-z0-9_]{1,15}$/.test(opt.user)) {
  console.error(`🐕 --user: "${opt.user}" isn't an X handle`);
  process.exit(2);
}
const keywords = opt.keyword.map((k) => k.trim()).filter(Boolean);

const barks = Math.max(1, Number(opt.barks) || 1);
const useWidget = widgetSupported() && !opt['no-widget'];

// Puts the notch widget (usage, Now Playing, the dog) on screen, building it on first run.
let widgetLaunchedAt = 0;
let widgetBroken = false;
async function startWidget() {
  // Just opened: it can take a moment to show up as running. A failed build isn't retried this run.
  if (!useWidget || widgetBroken || widgetRunning() || Date.now() - widgetLaunchedAt < 30_000) return;
  let result;
  try {
    result = await ensureWidget({ onBuild: () => log(t.widgetBuilding) });
  } catch (e) {
    result = { error: e.message };
  }
  const { app, error, fallback } = result;
  if (error) log(`${t.widgetFailed}\n${error}`);
  if (!app) {
    widgetBroken = true;
    return;
  }
  if (fallback) widgetBroken = true; // running the last good build; don't rebuild on every alert
  launchWidget(app);
  widgetLaunchedAt = Date.now();
  log(t.widgetUp);
}

if (opt['install-app']) {
  if (!widgetSupported()) {
    console.error(t.widgetMacOnly);
    process.exit(1);
  }
  const { error } = await installApp({ onBuild: () => log(t.widgetBuilding) });
  if (error) {
    log(`${t.widgetFailed}\n${error}`);
    process.exit(1);
  }
  log(t.appInstalled);
  process.exit(0);
}

async function alert(post) {
  showDog(barking(t.bubble));
  log(`🚨 ${post.text}`);
  if (post.url) log(post.url);
  notify(t.notifyTitle, post.text.slice(0, 180));
  if (opt.open && post.url) openUrl(post.url);
  // The widget picks this up and barks in the notch until it's read.
  try {
    writeAlert({
      id: post.id ?? `test-${Date.now()}`,
      title: t.alertTitle,
      body: post.text,
      url: post.url,
      woof: t.alertWoof,
      open: t.alertOpen,
      postedAt: post.createdAt,
    });
  } catch (e) {
    log(`⚠️  ${e.message}`);
  }
  await playBark(barks, opt.sound); // the bark never waits on the widget
  await startWidget(); // in case it was quit
}

if (opt.test) {
  await alert({ text: t.testPost, url: '' });
  process.exit(0);
}

const statePath = join(DIR, `${opt.user}.json`);
const seen = new Set((() => {
  try {
    const saved = JSON.parse(readFileSync(statePath, 'utf8')).seen;
    return Array.isArray(saved) ? saved.map(String) : [];
  } catch {
    return [];
  }
})());
const firstRun = seen.size === 0;

function save() {
  mkdirSync(dirname(statePath), { recursive: true });
  writeFileSync(statePath, JSON.stringify({ seen: [...seen].slice(-500) }));
}

await startWidget();

let source;
try {
  source = opt.rss
    ? rssSource({ url: opt.rss, username: opt.user })
    : xSource({ username: opt.user, bearerToken: process.env.X_BEARER_TOKEN, missingTokenMessage: t.noToken });
} catch (e) {
  showDog(SLEEPING);
  console.error(`🐕 ${e.message}\n   ${t.seeHelp}`);
  process.exit(1);
}

// Between 15 seconds and a day: anything else would hammer the feed or overflow setTimeout.
const seconds = Number(opt.interval) || (opt.rss ? 60 : 300);
const intervalMs = Math.min(Math.max(seconds, 15), 86_400) * 1000;
let primed = !firstRun || opt['bark-old'];

async function tick() {
  const posts = await source.fetch();
  const fresh = posts.filter((p) => p.id && !seen.has(p.id)).reverse(); // oldest first
  let barked = 0;
  for (const p of fresh) {
    seen.add(p.id);
    if (primed && isResetPost(p.text, keywords)) {
      barked++;
      await alert(p);
    }
  }
  if (!primed) log(t.primed(posts.length));
  else if (fresh.length && !barked) log(t.quiet(fresh.length));
  // An empty first fetch (a mirror's error page) doesn't count: priming waits for real posts.
  if (posts.length) primed = true;
  save();
}

showDog(WATCHING, t.watching(opt.user));
log(t.source(source.name, intervalMs / 1000));

while (true) {
  let wait = intervalMs;
  try {
    await tick();
    process.exitCode = 0;
  } catch (e) {
    process.exitCode = 1; // --once: let cron see a failed check
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

// The notch widget (macOS): usage, Now Playing and the dog, from the Swift app in ../app.
// `tibodog` builds it into ~/.tibodog on first run, launches it, and hands it resets through alert.json.

import { spawn, execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync, readdirSync, statSync, writeFileSync, mkdirSync, rmSync, cpSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const APP_SRC = fileURLToPath(new URL('../app', import.meta.url));
const DIR = process.env.TIBODOG_HOME ?? join(homedir(), '.tibodog');
const INSTALLED = '/Applications/TiboDog.app';

export const widgetSupported = () => process.platform === 'darwin' && existsSync(APP_SRC);

// Everything that goes into the app, so a new version of tibodog rebuilds it.
function sourceHash() {
  const hash = createHash('sha1');
  const walk = (p) => {
    const st = statSync(p);
    if (st.isDirectory()) {
      for (const name of readdirSync(p).sort()) {
        if (name === 'build' || name.startsWith('.')) continue;
        walk(join(p, name));
      }
    } else {
      hash.update(p.slice(APP_SRC.length)).update(readFileSync(p));
    }
  };
  for (const part of ['Package.swift', 'Sources', 'Resources', 'Scripts', 'Vendor']) walk(join(APP_SRC, part));
  return hash.digest('hex').slice(0, 10);
}

function builtApp() {
  return join(DIR, `widget-${sourceHash()}`, 'TiboDog.app');
}

function build(out) {
  return new Promise((resolve) => {
    const p = spawn('bash', [join(APP_SRC, 'Scripts', 'build-app.sh')], {
      env: { ...process.env, TIBODOG_APP_OUT: out, TIBODOG_SCRATCH: join(DIR, 'build') },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    let output = '';
    p.stdout.on('data', (d) => (output += d));
    p.stderr.on('data', (d) => (output += d));
    p.on('error', () => resolve({ ok: false, output }));
    p.on('exit', (code) => resolve({ ok: code === 0, output }));
  });
}

// Builds the widget into ~/.tibodog/widget-<version>, dropping builds of older versions.
async function buildInto(app, onBuild) {
  onBuild?.();
  if (existsSync(DIR)) {
    for (const name of readdirSync(DIR)) if (name.startsWith('widget-')) rmSync(join(DIR, name), { recursive: true, force: true });
  }
  const out = join(app, '..');
  mkdirSync(out, { recursive: true });
  const { ok, output } = await build(out);
  if (ok && existsSync(app)) return { app };
  return { error: output.trim().split('\n').slice(-5).join('\n') };
}

// The app to run: the installed one if there is one, else a build in ~/.tibodog (made on first run).
// Resolves to { app } or { error }.
export async function ensureWidget({ onBuild } = {}) {
  if (existsSync(INSTALLED)) return { app: INSTALLED };
  const app = builtApp();
  return existsSync(app) ? { app } : buildInto(app, onBuild);
}

export function widgetRunning() {
  try {
    execFileSync('pgrep', ['-x', 'TiboDog'], { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

// Opens it in the background; it keeps running after tibodog exits.
export function launchWidget(app) {
  spawn('open', ['-g', app], { stdio: 'ignore', detached: true }).unref();
}

// Optional: copy the widget to /Applications so it can start at login without tibodog.
export async function installApp({ onBuild } = {}) {
  const app = builtApp();
  if (!existsSync(app)) {
    const r = await buildInto(app, onBuild);
    if (r.error) return r;
  }
  try {
    execFileSync('pkill', ['-x', 'TiboDog'], { stdio: 'ignore' });
  } catch {
    // wasn't running
  }
  rmSync(INSTALLED, { recursive: true, force: true });
  cpSync(app, INSTALLED, { recursive: true });
  launchWidget(INSTALLED);
  return { app: INSTALLED };
}

// Leaves the reset for the widget, which barks in the notch until it's read. The widget marks it read
// by writing the id to alert-seen.
export function writeAlert({ id, title, body, url, woof, open }) {
  mkdirSync(DIR, { recursive: true });
  const alert = { id: String(id), title, body, url: url || null, woof, open, at: Date.now() / 1000 };
  writeFileSync(join(DIR, 'alert.json'), JSON.stringify(alert));
}

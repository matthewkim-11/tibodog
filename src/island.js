// macOS notch "dynamic island": a native helper compiled from island/TiboIsland.swift on first use.

import { spawn, execFile, execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { homedir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const SRC = fileURLToPath(new URL('./island/TiboIsland.swift', import.meta.url));
const DIR = join(homedir(), '.tibodog');
const PID_FILE = join(DIR, 'island.pid');

export const islandSupported = () => process.platform === 'darwin';

// One binary per source version, so upgrades rebuild automatically.
function binaryPath() {
  const hash = createHash('sha1').update(readFileSync(SRC)).digest('hex').slice(0, 10);
  return join(DIR, 'bin', `tibo-island-${hash}`);
}

let building = null;

// Resolves to the binary path, or null when it can't be built (no Xcode Command Line Tools).
export function prepareIsland({ onBuild } = {}) {
  if (!islandSupported()) return Promise.resolve(null);
  if (building) return building;
  const out = binaryPath();
  if (existsSync(out)) return (building = Promise.resolve(out));
  onBuild?.();
  mkdirSync(dirname(out), { recursive: true });
  building = new Promise((resolve) => {
    execFile('swiftc', ['-O', '-o', out, SRC], (err) => resolve(err ? null : out));
  });
  return building;
}

function killPrevious() {
  try {
    const pid = Number(readFileSync(PID_FILE, 'utf8'));
    // Only kill it if that pid is still our island, not some reused pid.
    const comm = execFileSync('ps', ['-p', String(pid), '-o', 'comm='], { encoding: 'utf8' });
    if (comm.includes('tibo-island')) process.kill(pid, 'SIGTERM');
  } catch {
    // no previous island
  }
}

// Shows the barking dog in the notch. It stays (even after tibodog exits) until you hover and read it.
export async function showIsland({ title, body, url, woof, open, lang }) {
  const bin = await prepareIsland();
  if (!bin) return false;
  killPrevious();
  const child = spawn(bin, [JSON.stringify({ title, body, url, woof, open, lang })], {
    detached: true,
    stdio: 'ignore',
  });
  child.unref();
  writeFileSync(PID_FILE, String(child.pid));
  return true;
}

// Leaves the reset for Islet (github.com/aiasapkr-beep/islet), which barks in its own notch island
// until it's read. Islet marks it read by writing the id to alert-seen.
export function writeAlert({ id, title, body, url, woof, open }) {
  mkdirSync(DIR, { recursive: true });
  const alert = { id: String(id), title, body, url: url || null, woof, open, at: Date.now() / 1000 };
  writeFileSync(join(DIR, 'alert.json'), JSON.stringify(alert));
}

export function isletRunning() {
  try {
    execFileSync('pgrep', ['-x', 'Islet'], { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

// Plays the bundled bark recording, or a synthesized bark as a fallback.

import { spawn } from 'node:child_process';
import { writeFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const RATE = 22050;

function bark(out, start, { pitch = 520, length = 0.22 } = {}) {
  const n = Math.floor(length * RATE);
  let phase = 0;
  for (let i = 0; i < n; i++) {
    const t = i / RATE;
    const p = t / length;
    // Pitch jumps up then falls off fast, like "rrWOOF".
    const f = pitch * (1 + 0.6 * Math.exp(-t * 60)) * (1 - 0.35 * p);
    phase += (2 * Math.PI * f) / RATE;
    let s = 0;
    for (let h = 1; h <= 6; h++) s += Math.sin(phase * h) / (h * 0.9);
    s += (Math.random() * 2 - 1) * 0.6 * Math.exp(-t * 25); // breathy attack
    const env = Math.min(1, t / 0.008) * Math.exp(-t * 14);
    out[start + i] += Math.tanh(s * 1.8) * env * 0.7;
  }
}

export function makeBarkWav(count = 2) {
  const gap = 0.12;
  const len = 0.22;
  const total = Math.ceil((count * (len + gap) + 0.1) * RATE);
  const samples = new Float32Array(total);
  for (let k = 0; k < count; k++) {
    bark(samples, Math.floor(k * (len + gap) * RATE), {
      pitch: 500 + Math.random() * 80 - (k % 2) * 40,
      length: len,
    });
  }
  const buf = Buffer.alloc(44 + total * 2);
  buf.write('RIFF', 0);
  buf.writeUInt32LE(36 + total * 2, 4);
  buf.write('WAVEfmt ', 8);
  buf.writeUInt32LE(16, 16);
  buf.writeUInt16LE(1, 20); // PCM
  buf.writeUInt16LE(1, 22); // mono
  buf.writeUInt32LE(RATE, 24);
  buf.writeUInt32LE(RATE * 2, 28);
  buf.writeUInt16LE(2, 32);
  buf.writeUInt16LE(16, 34);
  buf.write('data', 36);
  buf.writeUInt32LE(total * 2, 40);
  for (let i = 0; i < total; i++) {
    buf.writeInt16LE(Math.round(Math.max(-1, Math.min(1, samples[i])) * 32767), 44 + i * 2);
  }
  return buf;
}

function players(file) {
  if (process.platform === 'darwin') return [['afplay', [file]]];
  if (process.platform === 'win32') {
    return [['powershell', ['-NoProfile', '-c', `(New-Object Media.SoundPlayer '${file}').PlaySync()`]]];
  }
  return [
    ['paplay', [file]],
    ['aplay', ['-q', file]],
    ['ffplay', ['-nodisp', '-autoexit', '-loglevel', 'quiet', file]],
  ];
}

function run(cmd, args) {
  return new Promise((resolve) => {
    const p = spawn(cmd, args, { stdio: 'ignore' });
    p.on('error', () => resolve(false));
    p.on('exit', (code) => resolve(code === 0));
  });
}

// Real recording: "Barking of a dog" by Amada44, CC BY-SA 3.0 (see sounds/CREDITS.md).
const REAL_BARK = fileURLToPath(new URL('../sounds/bark.wav', import.meta.url));

let cached = null;

function synthFile() {
  if (!cached) {
    cached = join(tmpdir(), `tibodog-bark-${process.pid}.wav`);
    writeFileSync(cached, makeBarkWav(3));
  }
  return cached;
}

async function playOnce(file) {
  for (const [cmd, args] of players(file)) {
    if (await run(cmd, args)) return true;
  }
  return false;
}

// sound: a .wav path, 'synth' for the synthesized bark, or empty for the real recording.
export async function playBark(times = 1, sound) {
  let file;
  if (sound === 'synth') file = synthFile();
  else if (sound && existsSync(sound)) file = sound;
  else file = existsSync(REAL_BARK) ? REAL_BARK : synthFile();
  for (let i = 0; i < times; i++) {
    if (!(await playOnce(file))) {
      process.stdout.write('\x07'); // no audio player found: terminal bell, still a bark
      return false;
    }
  }
  return true;
}

export function notify(title, message) {
  if (process.platform === 'darwin') {
    const esc = (s) => s.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
    return run('osascript', ['-e', `display notification "${esc(message)}" with title "${esc(title)}"`]);
  }
  if (process.platform === 'linux') return run('notify-send', [title, message]);
  return Promise.resolve(false);
}

export function openUrl(url) {
  const cmd = process.platform === 'darwin' ? 'open' : process.platform === 'win32' ? 'explorer' : 'xdg-open';
  return run(cmd, [url]);
}

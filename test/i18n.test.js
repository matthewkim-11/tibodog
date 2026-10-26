import { test } from 'node:test';
import assert from 'node:assert/strict';
import { detectLang, getMessages, LANGS } from '../src/i18n.js';
import { barking } from '../src/dog.js';

test('explicit language wins, unknown falls back to en', () => {
  assert.equal(detectLang('ko'), 'ko');
  assert.equal(detectLang('ko_KR.UTF-8'), 'ko');
  assert.equal(detectLang('EN'), 'en');
  assert.equal(detectLang('fr'), 'en');
});

test('every language has every message', () => {
  const keys = Object.keys(getMessages('en')).sort();
  for (const l of LANGS) assert.deepEqual(Object.keys(getMessages(l)).sort(), keys, l);
});

test('speech bubble lines up with Hangul', () => {
  const lines = barking(getMessages('ko').bubble).split('\n').filter((l) => l.includes('|'));
  const cols = (s) => [...s].reduce((w, ch) => w + (/[가-힣]/.test(ch) ? 2 : 1), 0);
  const ends = new Set(lines.map(cols));
  assert.equal(ends.size, 1, lines.join('\n'));
});

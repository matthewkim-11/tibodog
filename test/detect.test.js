import { test } from 'node:test';
import assert from 'node:assert/strict';
import { isResetPost } from '../src/detect.js';
import { parseFeed } from '../src/sources.js';

test('barks at reset announcements', () => {
  for (const t of [
    'We have reset Codex rate limits across all plans. Enjoy!',
    'Resetting usage limits tonight after we found some issues.',
    'Codex limits will be reset within 24 hours',
    'Weekly limits refreshed for everyone 🎉',
    '코덱스 사용량 리셋했습니다',
  ]) assert.ok(isResetPost(t), t);
});

test('stays quiet otherwise', () => {
  for (const t of [
    'Shipping a new Codex model today',
    'Had to factory reset my phone, limits of patience',
    'What a great week for the team',
  ]) assert.ok(!isResetPost(t), t);
});

test('extra keywords always trigger', () => {
  assert.ok(isResetPost('free tokens for all', ['free tokens']));
});

test('parses rss and atom', () => {
  const rss = `<rss><channel><item><title>Limits reset</title><description><![CDATA[<p>We reset Codex limits &amp; more</p>]]></description><link>https://x.com/thsottiaux/status/1</link><guid>1</guid></item></channel></rss>`;
  const [a] = parseFeed(rss);
  assert.equal(a.id, '1');
  assert.equal(a.text, 'We reset Codex limits & more');
  const atom = `<feed><entry><id>tag:2</id><title>hi</title><link href="https://x.com/a/status/2"/></entry></feed>`;
  const [b] = parseFeed(atom);
  assert.equal(b.url, 'https://x.com/a/status/2');
});

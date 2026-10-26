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
    // Tibo's own posts, October 2026
    'Day 21/ Wonder what happens the remaining seven days. But today is a reset.',
    'Day 17/ Bet you thought we forgot, but no, it’s reset day today.',
    "Day 15/ Nevermind, we're still cooking... and reset. Enjoy.",
    'Back at the laptop. The usage limits have been reset for all paid users of Codex and ChatGPT Work.',
  ]) assert.ok(isResetPost(t), t);
});

test('stays quiet otherwise', () => {
  for (const t of [
    'Shipping a new Codex model today',
    'Had to factory reset my phone, limits of patience',
    'What a great week for the team',
    'Lands tomorrow before 10am PST.',
    "Fully included in the Pro plan, doesn't draw on your weekly usage.",
    'When is the next reset?',
    'Please reset your password via the link',
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

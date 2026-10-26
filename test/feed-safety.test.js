import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseFeed, isPostUrl } from '../src/sources.js';

const item = (inner) => `<rss><channel><item>${inner}</item></channel></rss>`;

test('a feed link never becomes a file, app or other scheme', () => {
  for (const link of ['file:///System/Applications/Calculator.app', 'vscode://x', 'smb://evil/share', '-a Calculator']) {
    const [p] = parseFeed(item(`<title>We reset the limits</title><link>${link}</link><guid>${link}</guid>`), 'thsottiaux');
    assert.equal(p.url, null, link);
  }
  // Any host's /status/<id> only ever turns into that post on x.com.
  const [q] = parseFeed(item('<link>https://evil.com/x/status/1234567</link>'), 'thsottiaux');
  assert.equal(q.url, 'https://x.com/thsottiaux/status/1234567');
  assert.ok(isPostUrl('https://x.com/thsottiaux/status/2114588174249071102'));
  assert.ok(!isPostUrl('http://x.com/thsottiaux/status/2114588174249071102'));
  assert.ok(!isPostUrl('https://x.com.evil.com/a/status/2114588174249071102'));
});

test('control characters and terminal escapes are dropped', () => {
  const [p] = parseFeed(item('<title>We reset the limits &#0; &#27;]0;pwned&#7; &#27;[31mred</title>'), 'a');
  assert.doesNotMatch(p.text, /[\u0000-\u0008\u000b-\u001f\u007f-\u009f]/);
});

test('odd entities and escaped HTML are handled', () => {
  const [p] = parseFeed(item('<title>x &#99999999; &#x1F415; ok</title>'), 'a');
  assert.equal(p.text, 'x 🐕 ok');
  const [q] = parseFeed(item('<description>&lt;p&gt;new blog post &lt;a href="https://e.com/how-we-reset-rate-limits"&gt;link&lt;/a&gt;&lt;/p&gt;</description>'), 'a');
  assert.equal(q.text, 'new blog post link');
});

test('malformed feeds stay fast', () => {
  for (const junk of ['<item '.repeat(100_000), '<item><title '.repeat(50_000), '<![CDATA['.repeat(100_000)]) {
    const start = Date.now();
    parseFeed(junk, 'a');
    assert.ok(Date.now() - start < 1000, `took ${Date.now() - start}ms`);
  }
});

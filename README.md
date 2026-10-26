# 🐕 tibodog

> 티보가 리셋하면 짖는 개.
> A dog that barks when Tibo resets the limits.

```
      / \__            _______________
     (    O\___       |  WOOF! WOOF!  |
     /         O  <== | RESET! RESET! |
    /   (_____/       |_______________|
   /_____/   U
```

Tibo ([@thsottiaux](https://x.com/thsottiaux)) posts on X whenever the Codex usage limits get reset.
tibodog watches his feed, and when a reset post shows up it:

- 🔊 **barks** with a real dog recording (or a synthesized bark with `--sound synth`)
- 🐶 **barks in your notch** on macOS until you look (see below)
- 🔔 pops a desktop notification (macOS / Linux)
- 🌐 opens the post if you pass `--open`

Zero dependencies. Node 18+. macOS, Linux, Windows.

## 빠른 시작 / Quick start

```bash
npx tibodog --test        # 지금 바로 한번 짖어보기 / bark once right now
```

Then pick a way to read X:

### A) 공식 X API / Official X API

```bash
export X_BEARER_TOKEN=xxxxxxxx
npx tibodog
```

Reading a user timeline needs a paid X API tier. The default poll is every 5 minutes to stay
under rate limits. On a 429 the dog naps until the limit resets (the irony is noted).

### B) RSS 미러 / Any RSS mirror (free)

Any RSS/Atom feed of the account works: a Nitter instance, self-hosted [RSSHub](https://docs.rsshub.app)
(`/twitter/user/thsottiaux`), rss.app, and so on.

```bash
npx tibodog --rss "https://your-rsshub.example.com/twitter/user/thsottiaux"
```

## 옵션 / Options

| flag | default | |
|---|---|---|
| `--user <handle>` | `thsottiaux` | 감시할 계정 / account to watch |
| `--rss <url>` | | use an RSS feed instead of the X API |
| `--interval <sec>` | 60 (RSS) / 300 (X) | poll interval |
| `--keyword <text>` | | extra trigger phrase, repeatable |
| `--barks <n>` | 1 | 짖는 소리 반복 횟수 / times to play the bark |
| `--sound <file.wav\|synth>` | real recording | bring your own dog, or `synth` for the synthesized bark |
| `--lang <ko\|en>` | system locale | 표시 언어 / UI language |
| `--open` | off | open the post in the browser |
| `--no-island` | | 노치 강아지 끄기 / no notch dog (macOS) |
| `--bark-old` | off | also bark at reset posts already in the feed on startup |
| `--once` | off | check once and exit (for cron) |
| `--test` | | just bark |

You can also set these through env vars: `TIBODOG_USER`, `TIBODOG_RSS`, `TIBODOG_INTERVAL`, `TIBODOG_SOUND`, `TIBODOG_LANG`.

## 언어 / Language

한국어(`ko`)와 영어(`en`)를 지원해요. 따로 지정하지 않으면 시스템 언어(`LANG`)를 따라가요.

```bash
npx tibodog --lang ko     # 멍! 멍멍! 리셋이다! 리셋!
npx tibodog --lang en     # WOOF! WOOF! RESET! RESET!
```

Order: `--lang` → `TIBODOG_LANG` → `LC_ALL` / `LC_MESSAGES` / `LANG` → system locale → `en`.
To add a language, add an entry to [`src/i18n.js`](src/i18n.js).

## 노치 강아지 / The notch dog (macOS)

리셋이 오면 노치(다이나믹 아일랜드 자리) 양옆에 강아지가 나와서 계속 짖어요.
마우스를 올리면 펼쳐져서 티보의 글이 보이고, 다 읽고 마우스를 떼면 노치 안으로 쏙 들어가요.
살짝 스치기만 하면 확인한 걸로 치지 않고 계속 짖어요.

When a reset lands, a dog appears on both sides of the notch and keeps barking. Hover to read the post,
move away and it tucks back into the notch. A quick brush doesn't count as read. It stays even if you
quit tibodog, so a reset you missed while away is still waiting for you.

```
 ┌──────────┬────────┬──────────┐
 │ 🐕 ))    │ notch  │    멍!   │   ← keeps barking
 └──────────┴────────┴──────────┘
              hover ↓
 ┌──────────────────────────────────────────┐
 │ 🐕   티보가 리셋했어요!            지금 │
 │      We just reset Codex rate limits...  │
 │      X에서 보기 ↗                        │
 └──────────────────────────────────────────┘
```

- Native SwiftUI helper in [`src/island/TiboIsland.swift`](src/island/TiboIsland.swift), compiled on first run
  into `~/.tibodog/bin` (needs Xcode Command Line Tools: `xcode-select --install`).
- Works on Macs without a notch too: it shows as a black pill at the top center.
- Sits above other notch apps (NotchNook, Islet, ...) so a reset never hides behind them.

## 어떻게 판단하나 / How it decides

A post counts as a reset post when it has a reset word (`reset`, `resetting`, `refreshed`, `리셋`, `초기화`)
**and** a limits word (`limits`, `usage`, `rate`, `codex`, `weekly`, `사용량`, `한도`, ...).
See [`src/detect.js`](src/detect.js). If the dog barks at the wrong thing, send a PR with a test case.

On the first run it only records the posts already in the feed, so it won't bark at old ones.
Seen IDs are stored in `~/.tibodog/<user>.json`.

## 개발 / Development

```bash
npm test
```

## 소리 출처 / Sound credits

The bundled bark is ["Barking of a dog"](https://commons.wikimedia.org/wiki/File:Barking_of_a_dog.ogg)
by Amada44 on Wikimedia Commons, licensed [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/).
The audio file keeps that license. The code is MIT. Details in [`sounds/CREDITS.md`](sounds/CREDITS.md).

## Disclaimer

A fan-made joke project. Not affiliated with OpenAI or X. Be nice to Tibo. 🐶

MIT

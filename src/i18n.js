// UI strings. Add a language by adding a key here.

const messages = {
  en: {
    bubble: ['WOOF! WOOF!', 'RESET! RESET!'],
    watching: (u) => `👀  watching @${u}`,
    notifyTitle: '🐕 WOOF! Tibo reset the limits!',
    testPost: 'Test bark. We have reset Codex rate limits for all plans. Enjoy!',
    source: (name, sec) => `source: ${name}, every ${sec}s`,
    primed: (n) => `sniffed ${n} existing posts, ignoring them. waiting for new ones...`,
    quiet: (n) => `${n} new post(s), no reset. good boy stays quiet.`,
    rateLimited: (sec) => `rate limited 💤 napping ${sec}s`,
    noToken: 'X_BEARER_TOKEN is not set (or use --rss <url>)',
    seeHelp: 'run `tibodog --help` for setup.',
    alertTitle: 'Tibo reset the limits!',
    alertWoof: 'WOOF!',
    alertOpen: 'Open on X',
    widgetBuilding: 'building the notch widget (first run only, under a minute)...',
    widgetFailed: "couldn't start the notch widget. It needs Xcode Command Line Tools (xcode-select --install).",
    widgetUp: 'notch widget is up: usage · music · the dog',
    widgetMacOnly: 'the notch widget is macOS only.',
    appInstalled: 'installed /Applications/TiboDog.app. Turn on "Launch at Login" in its menu to start it with your Mac.',
    help: `tibodog 🐕 — barks when Tibo (@thsottiaux) resets the limits

Usage: tibodog [options]

Sources (pick one):
  X_BEARER_TOKEN=...        use the official X API v2 (default if set)
  --rss <url>               poll any RSS/Atom mirror of the account (Nitter, RSSHub, rss.app)

Options:
  --user <handle>           account to watch (default: thsottiaux)
  --interval <sec>          poll interval (default: 60 for RSS, 300 for X API)
  --keyword <text>          extra trigger phrase, repeatable
  --barks <n>               times to play the bark per alert (default: 1)
  --sound <file.wav|synth>  your own dog, or 'synth' for the synthesized bark
  --lang <ko|en>            UI language (default: from your system locale)
  --open                    open the post in the browser when barking
  --no-widget               don't start the notch widget (macOS)
  --install-app             install the widget as /Applications/TiboDog.app and exit (optional)
  --bark-old                also bark at reset posts already in the feed on startup
  --once                    check once and exit (for cron)
  --test                    just bark, right now
`,
  },
  ko: {
    bubble: ['멍! 멍멍!', '리셋이다! 리셋!'],
    watching: (u) => `👀  @${u} 감시 중`,
    notifyTitle: '🐕 멍멍! 티보가 리셋했다!',
    testPost: '테스트 멍멍. We have reset Codex rate limits for all plans. Enjoy!',
    source: (name, sec) => `소스: ${name}, ${sec}초마다 확인`,
    primed: (n) => `기존 글 ${n}개 냄새만 맡고 넘어감. 새 글 기다리는 중...`,
    quiet: (n) => `새 글 ${n}개, 리셋 아님. 착한 개는 조용히 있음.`,
    rateLimited: (sec) => `요청 한도 초과 💤 ${sec}초 낮잠`,
    noToken: 'X_BEARER_TOKEN이 설정되지 않았어요 (또는 --rss <url> 사용)',
    seeHelp: '설정 방법은 `tibodog --help` 참고.',
    alertTitle: '티보가 리셋했어요!',
    alertWoof: '멍!',
    alertOpen: 'X에서 보기',
    widgetBuilding: '노치 위젯 빌드 중 (처음 한 번만, 1분 안 걸려요)...',
    widgetFailed: '노치 위젯을 띄우지 못했어요. Xcode Command Line Tools가 필요해요 (xcode-select --install).',
    widgetUp: '노치 위젯 실행 중: 사용량 · 음악 · 개',
    widgetMacOnly: '노치 위젯은 macOS에서만 돼요.',
    appInstalled: '/Applications/TiboDog.app에 설치했어요. 메뉴에서 "Launch at Login"을 켜면 맥을 켤 때 같이 떠요.',
    help: `tibodog 🐕
티보(@thsottiaux)가 리셋하면 짖는 개

사용법: tibodog [옵션]

소스 (하나 선택):
  X_BEARER_TOKEN=...        공식 X API v2 사용 (설정돼 있으면 기본값)
  --rss <url>               계정의 RSS/Atom 미러 폴링 (Nitter, RSSHub, rss.app)

옵션:
  --user <handle>           감시할 계정 (기본: thsottiaux)
  --interval <초>           확인 주기 (기본: RSS 60초, X API 300초)
  --keyword <텍스트>        추가 트리거 문구, 여러 번 지정 가능
  --barks <n>               알림당 짖는 소리 반복 횟수 (기본: 1)
  --sound <file.wav|synth>  내 개 소리 파일, 또는 synth로 합성 소리 사용
  --lang <ko|en>            표시 언어 (기본: 시스템 언어)
  --open                    짖을 때 브라우저로 글 열기
  --no-widget               노치 위젯 띄우지 않기 (macOS)
  --install-app             위젯을 /Applications/TiboDog.app으로 설치하고 끝내기 (선택)
  --bark-old                시작할 때 피드에 이미 있는 리셋 글에도 짖기
  --once                    한 번만 확인하고 종료 (cron용)
  --test                    지금 바로 짖기
`,
  },
};

export const LANGS = Object.keys(messages);

export function detectLang(explicit) {
  const raw =
    explicit ||
    process.env.TIBODOG_LANG ||
    process.env.LC_ALL ||
    process.env.LC_MESSAGES ||
    process.env.LANG ||
    Intl.DateTimeFormat().resolvedOptions().locale;
  const code = String(raw ?? '').toLowerCase().slice(0, 2);
  return LANGS.includes(code) ? code : 'en';
}

export function getMessages(lang) {
  return messages[lang] ?? messages.en;
}

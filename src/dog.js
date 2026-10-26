// Terminal dog.

export const SLEEPING = String.raw`
      / \__
     (    @\___     z
     /         O   z
    /   (_____/   z
   /_____/   U
`;

export const WATCHING = String.raw`
      / \__
     (    o\___
     /         O    %TEXT%
    /   (_____/
   /_____/   U
`;

// Hangul, CJK and emoji take two terminal columns.
const WIDE = /[ᄀ-ᅟ⺀-꓏가-힣豈-﫿︰-﹏＀-｠￠-￦]|\p{Extended_Pictographic}/u;
const width = (s) => [...s].reduce((w, ch) => w + (WIDE.test(ch) ? 2 : 1), 0);
const pad = (s, w) => s + ' '.repeat(w - width(s));

export function barking([line1, line2]) {
  const w = Math.max(width(line1), width(line2)) + 2;
  const bar = '_'.repeat(w);
  return [
    '',
    `      / \\__            ${bar}`,
    `     (    O\\___       | ${pad(line1, w - 2)} |`,
    `     /         O  <== | ${pad(line2, w - 2)} |`,
    `    /   (_____/       |${bar}|`,
    `   /_____/   U`,
    '',
  ].join('\n');
}

const isTTY = process.stdout.isTTY;
const yellow = (s) => (isTTY ? `\x1b[33m${s}\x1b[0m` : s);
const dim = (s) => (isTTY ? `\x1b[2m${s}\x1b[0m` : s);

export function showDog(frame, text = '') {
  console.log(yellow(frame.replace('%TEXT%', text)));
}

export function log(msg) {
  console.log(dim(`[${new Date().toLocaleTimeString()}]`), msg);
}

// Decides whether a post is a "limits got reset" announcement.

const RESET = /\b(re-?set(s|ting)?|refresh(ed|ing)?|wiped)\b|리셋|초기화/i;
const CONTEXT = /\b(limits?|usage|rate|quotas?|codex|plans?|weekly|5h|allowance)\b|사용량|한도/i;
// Cheap guard against obvious non-announcements ("password reset", "factory reset").
const NOISE = /\b(password|factory|hard reset|git reset)\b/i;

export function isResetPost(text, extraKeywords = []) {
  if (!text) return false;
  if (extraKeywords.some((k) => text.toLowerCase().includes(k.toLowerCase()))) return true;
  if (NOISE.test(text)) return false;
  return RESET.test(text) && CONTEXT.test(text);
}

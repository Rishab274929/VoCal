// Transcript normalization: lowercase, strip filler words, collapse whitespace,
// stable cache key generation.

const FILLER = new Set([
  "uh", "um", "uhh", "umm", "like", "you", "know", "so", "just", "really",
  "actually", "basically", "i", "ate", "had", "got", "have", "having",
  "a", "an", "the", "some", "of"
]);

export function normalize(transcript: string): string {
  return transcript
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s'-]/gu, " ")
    .split(/\s+/)
    .filter(t => t && !FILLER.has(t))
    .join(" ")
    .trim();
}

export function cacheKey(transcript: string, followUp?: string | null): string {
  const norm = normalize(transcript);
  const fu = followUp ? `|${normalize(followUp)}` : "";
  return `meal:${norm}${fu}`;
}

export function guessSlot(now = new Date()): "breakfast" | "lunch" | "dinner" | "snack" {
  const h = now.getHours();
  if (h >= 5 && h < 11) return "breakfast";
  if (h >= 11 && h < 15) return "lunch";
  if (h >= 17 && h < 22) return "dinner";
  return "snack";
}

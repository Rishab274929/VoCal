import { describe, it, expect } from "vitest";
import { normalize, cacheKey, guessSlot } from "../../src/lib/normalize";

// ---------------------------------------------------------------------------
// normalize
// ---------------------------------------------------------------------------
describe("normalize", () => {
  it("strips filler words, lowercases, strips punctuation, collapses whitespace", () => {
    expect(normalize("Uh, I had some Chicken Tikka Masala!!!")).toBe(
      "chicken tikka masala"
    );
    expect(normalize("Um like I ate a large   pepperoni pizza")).toBe(
      "large pepperoni pizza"
    );
  });

  it("preserves hyphens and apostrophes in words", () => {
    expect(normalize("mac-and-cheese with mom's recipe")).toBe(
      "mac-and-cheese with mom's recipe"
    );
  });

  it("returns empty string for empty input", () => {
    expect(normalize("")).toBe("");
  });

  it("returns empty string when input is only filler words", () => {
    expect(normalize("uh um like i had a the some of")).toBe("");
  });
});

// ---------------------------------------------------------------------------
// cacheKey
// ---------------------------------------------------------------------------
describe("cacheKey", () => {
  it("returns meal:<normalized> for a basic transcript", () => {
    expect(cacheKey("I had Two Tacos")).toBe("meal:two tacos");
  });

  it("appends |<normalized followUp> when followUp is provided", () => {
    expect(cacheKey("I had Two Tacos", "with extra cheese")).toBe(
      "meal:two tacos|with extra cheese"
    );
  });

  it("omits followUp segment when followUp is null", () => {
    expect(cacheKey("I had Two Tacos", null)).toBe("meal:two tacos");
  });

  it("omits followUp segment when followUp is undefined", () => {
    expect(cacheKey("I had Two Tacos", undefined)).toBe("meal:two tacos");
  });
});

// ---------------------------------------------------------------------------
// guessSlot
// ---------------------------------------------------------------------------
describe("guessSlot", () => {
  const at = (hour: number) => new Date(2026, 0, 1, hour, 0, 0);

  it("returns breakfast for 7 AM", () => {
    expect(guessSlot(at(7))).toBe("breakfast");
  });

  it("returns lunch for 12 PM", () => {
    expect(guessSlot(at(12))).toBe("lunch");
  });

  it("returns dinner for 6 PM", () => {
    expect(guessSlot(at(18))).toBe("dinner");
  });

  it("returns snack for 3 PM (gap between lunch and dinner)", () => {
    expect(guessSlot(at(15))).toBe("snack");
  });

  it("returns snack for 11 PM (after dinner window)", () => {
    expect(guessSlot(at(23))).toBe("snack");
  });
});

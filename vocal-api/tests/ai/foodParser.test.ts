import { describe, it, expect, vi, beforeEach } from "vitest";
import { parseTranscript } from "../../src/ai/foodParser";
import { chat } from "../../src/ai/llmClient";
import { usdaSearch } from "../../src/ai/usda";
import { mockKV } from "../helpers/mocks";
import type { Env, VoiceParseResponse } from "../../src/types";

// ---------------------------------------------------------------------------
// Mocks — LLM and USDA are external services; stub them.
// Canon (matchChain / parseChipotleBowl) is NOT mocked so we get
// integration coverage of the chain-resolution path.
// ---------------------------------------------------------------------------
vi.mock("../../src/ai/llmClient", () => ({
  chat: vi.fn(),
}));

vi.mock("../../src/ai/usda", () => ({
  usdaSearch: vi.fn(),
}));

const mockChat = chat as ReturnType<typeof vi.fn>;
const mockUsda = usdaSearch as ReturnType<typeof vi.fn>;

// Minimal Env with no KV and no API keys — tests that need them override.
function baseEnv(overrides: Partial<Env> = {}): Env {
  return { WAFER_API_KEY: "test-key", ...overrides };
}

// ---------------------------------------------------------------------------
// parseTranscript
// ---------------------------------------------------------------------------
describe("parseTranscript", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  // -----------------------------------------------------------------------
  // 1. Empty transcript
  // -----------------------------------------------------------------------
  it("returns follow_up_question for an empty transcript", async () => {
    const res = await parseTranscript("", null, baseEnv());

    expect(res.meal).toBeNull();
    expect(res.follow_up_question).toBe("What did you eat?");
    expect(res.transcript).toBe("");
    // LLM should never be called for empty input
    expect(mockChat).not.toHaveBeenCalled();
  });

  // -----------------------------------------------------------------------
  // 2. Whitespace-only transcript
  // -----------------------------------------------------------------------
  it("returns follow_up_question for a whitespace-only transcript", async () => {
    const res = await parseTranscript("   \n\t  ", null, baseEnv());

    expect(res.meal).toBeNull();
    expect(res.follow_up_question).toBe("What did you eat?");
    expect(mockChat).not.toHaveBeenCalled();
  });

  // -----------------------------------------------------------------------
  // 3. Chain canon match (real matchChain — no mock)
  // -----------------------------------------------------------------------
  it("returns chain meal for a McDonald's Big Mac transcript", async () => {
    const res = await parseTranscript("mcdonald's big mac", null, baseEnv());

    expect(res.meal).not.toBeNull();
    expect(res.meal!.name).toBe("McDonald's Big Mac");
    expect(res.meal!.kcal).toBe(590);
    expect(res.meal!.protein_g).toBe(25);
    expect(res.meal!.carbs_g).toBe(45);
    expect(res.meal!.fat_g).toBe(34);
    expect(res.meal!.confidence).toBe(0.95);
    expect(res.meal!.source).toBe("voice");
    expect(res.follow_up_question).toBeNull();
    expect(res.reasoning).toContain("chain canon");
    // LLM should be skipped for chain matches
    expect(mockChat).not.toHaveBeenCalled();
  });

  // -----------------------------------------------------------------------
  // 4. Chipotle bowl with guac, no answer -> follow-up
  // -----------------------------------------------------------------------
  it("returns follow_up when Chipotle bowl mentions guac with no answer", async () => {
    const res = await parseTranscript(
      "chipotle bowl with guac",
      null,
      baseEnv()
    );

    expect(res.meal).toBeNull();
    expect(res.follow_up_question).toBe("Single scoop of guac?");
    expect(res.reasoning).toBeTruthy();
    expect(mockChat).not.toHaveBeenCalled();
  });

  // -----------------------------------------------------------------------
  // 5. LLM returns valid JSON -> parsed meal with confidence clamped
  // -----------------------------------------------------------------------
  it("parses a valid LLM JSON response and clamps confidence to [0,1]", async () => {
    mockChat.mockResolvedValueOnce({
      content: JSON.stringify({
        name: "Scrambled Eggs",
        detail: "Two large eggs, butter",
        kcal: 220,
        protein_g: 14,
        carbs_g: 2,
        fat_g: 17,
        slot: "breakfast",
        confidence: 1.5, // should be clamped to 1
        sodium_mg: 320,
        fiber_g: 0,
      }),
      provider: "wafer",
      model: "test-model",
      latencyMs: 42,
    });

    const res = await parseTranscript("two scrambled eggs", null, baseEnv());

    expect(res.meal).not.toBeNull();
    expect(res.meal!.name).toBe("Scrambled Eggs");
    expect(res.meal!.kcal).toBe(220);
    expect(res.meal!.protein_g).toBe(14);
    expect(res.meal!.carbs_g).toBe(2);
    expect(res.meal!.fat_g).toBe(17);
    expect(res.meal!.slot).toBe("breakfast");
    expect(res.meal!.source).toBe("voice");
    // confidence > 1 must be clamped
    expect(res.meal!.confidence).toBe(1);
    // micros should carry through
    expect(res.meal!.sodium_mg).toBe(320);
    expect(res.meal!.fiber_g).toBe(0);
    expect(res.follow_up_question).toBeNull();
    expect(res.reasoning).toContain("wafer");
  });

  it("clamps negative confidence to 0", async () => {
    mockChat.mockResolvedValueOnce({
      content: JSON.stringify({
        name: "Mystery Snack",
        detail: "Not sure",
        kcal: 100,
        protein_g: 5,
        carbs_g: 10,
        fat_g: 3,
        slot: "snack",
        confidence: -0.5,
      }),
      provider: "wafer",
      model: "test-model",
      latencyMs: 10,
    });

    const res = await parseTranscript("mystery snack", null, baseEnv());
    expect(res.meal!.confidence).toBe(0);
  });

  // -----------------------------------------------------------------------
  // 6. LLM returns follow_up_question -> forwarded, meal null
  // -----------------------------------------------------------------------
  it("forwards LLM follow_up_question with meal null", async () => {
    mockChat.mockResolvedValueOnce({
      content: JSON.stringify({
        follow_up_question: "Was that a small or large coffee?",
        reasoning: "Size affects calorie count significantly.",
      }),
      provider: "wafer",
      model: "test-model",
      latencyMs: 30,
    });

    const res = await parseTranscript("coffee", null, baseEnv());

    expect(res.meal).toBeNull();
    expect(res.follow_up_question).toBe(
      "Was that a small or large coffee?"
    );
    expect(res.reasoning).toContain("Size affects");
  });

  // -----------------------------------------------------------------------
  // 7. LLM throws, USDA fallback succeeds
  // -----------------------------------------------------------------------
  it("falls back to USDA when LLM throws", async () => {
    mockChat.mockRejectedValueOnce(new Error("rate limited"));
    mockUsda.mockResolvedValueOnce({
      kcal: 95,
      protein_g: 0.5,
      carbs_g: 25,
      fat_g: 0.3,
      description: "Apple, raw, with skin",
      servingGrams: 182,
      fdcId: 171688,
    });

    const res = await parseTranscript("an apple", null, baseEnv());

    expect(res.meal).not.toBeNull();
    expect(res.meal!.name).toBe("Apple, raw, with skin");
    expect(res.meal!.kcal).toBe(95);
    expect(res.meal!.protein_g).toBe(1); // Math.round(0.5)
    expect(res.meal!.carbs_g).toBe(25);
    expect(res.meal!.fat_g).toBe(0);     // Math.round(0.3)
    expect(res.meal!.confidence).toBe(0.65);
    expect(res.meal!.detail).toContain("USDA");
    expect(res.meal!.detail).toContain("171688");
    expect(res.follow_up_question).toBeNull();
    expect(res.reasoning).toContain("USDA fallback");
    expect(res.reasoning).toContain("rate limited");
  });

  // -----------------------------------------------------------------------
  // 8. All tiers fail -> meal null, follow-up asking for specifics
  // -----------------------------------------------------------------------
  it("returns null meal and follow-up when all tiers fail", async () => {
    mockChat.mockRejectedValueOnce(new Error("all providers down"));
    mockUsda.mockResolvedValueOnce(null);

    const res = await parseTranscript(
      "some weird food nobody knows",
      null,
      baseEnv()
    );

    expect(res.meal).toBeNull();
    expect(res.follow_up_question).toBeTruthy();
    expect(res.follow_up_question).toContain("describe it");
    expect(res.reasoning).toContain("No matcher confident");
  });

  // -----------------------------------------------------------------------
  // 9. KV cache hit -> returns cached response
  // -----------------------------------------------------------------------
  it("returns cached response from FOOD_KV on cache hit", async () => {
    const cached: VoiceParseResponse = {
      transcript: "stale-transcript", // will be overwritten
      follow_up_question: null,
      meal: {
        name: "Cached Burrito",
        detail: "From KV",
        kcal: 600,
        protein_g: 30,
        carbs_g: 50,
        fat_g: 25,
        slot: "lunch",
        source: "voice",
        confidence: 0.9,
      },
      reasoning: "Originally parsed by LLM.",
    };

    const kv = mockKV({ "meal:cached burrito": JSON.stringify(cached) });
    const env = baseEnv({ FOOD_KV: kv });

    const res = await parseTranscript("cached burrito", null, env);

    expect(res.meal).not.toBeNull();
    expect(res.meal!.name).toBe("Cached Burrito");
    expect(res.meal!.kcal).toBe(600);
    // transcript should reflect the actual input, not the stale cached one
    expect(res.transcript).toBe("cached burrito");
    // reasoning should indicate cache hit
    expect(res.reasoning).toContain("Cache hit");
    // LLM should never be called on a cache hit
    expect(mockChat).not.toHaveBeenCalled();
    expect(kv.get).toHaveBeenCalled();
  });

  // -----------------------------------------------------------------------
  // Edge cases
  // -----------------------------------------------------------------------
  it("strips ```json fences from LLM output", async () => {
    const fenced = '```json\n{"name":"Toast","detail":"1 slice","kcal":80,"protein_g":3,"carbs_g":14,"fat_g":1,"slot":"breakfast","confidence":0.8}\n```';
    mockChat.mockResolvedValueOnce({
      content: fenced,
      provider: "wafer",
      model: "test-model",
      latencyMs: 20,
    });

    const res = await parseTranscript("a piece of toast", null, baseEnv());
    expect(res.meal).not.toBeNull();
    expect(res.meal!.name).toBe("Toast");
    expect(res.meal!.kcal).toBe(80);
  });

  it("rejects LLM output with out-of-range macros (kcal > 5000)", async () => {
    mockChat.mockResolvedValueOnce({
      content: JSON.stringify({
        name: "Hallucinated Feast",
        detail: "Way too much",
        kcal: 9999,
        protein_g: 10,
        carbs_g: 20,
        fat_g: 5,
        slot: "dinner",
        confidence: 0.5,
      }),
      provider: "wafer",
      model: "test-model",
      latencyMs: 10,
    });
    // USDA also returns nothing — should fall through to tier 5
    mockUsda.mockResolvedValueOnce(null);

    const res = await parseTranscript("hallucinated feast", null, baseEnv());
    // isValidMeal rejects kcal >= 5000, so the LLM result is dropped.
    // No USDA fallback either (LLM didn't throw, it just returned invalid data),
    // so we fall through to the "no tier confident" path.
    expect(res.meal).toBeNull();
    expect(res.follow_up_question).toBeTruthy();
  });

  it("filters out-of-range micronutrients from LLM output", async () => {
    mockChat.mockResolvedValueOnce({
      content: JSON.stringify({
        name: "Rice Bowl",
        detail: "White rice",
        kcal: 250,
        protein_g: 5,
        carbs_g: 55,
        fat_g: 1,
        slot: "lunch",
        confidence: 0.85,
        sodium_mg: 50,         // valid
        fiber_g: 200,          // over max of 100 -> filtered
        iron_mg: 2.3,          // valid, should keep one decimal
        vitamin_c_mg: 9999,    // over max of 2000 -> filtered
      }),
      provider: "wafer",
      model: "test-model",
      latencyMs: 15,
    });

    const res = await parseTranscript("bowl of rice", null, baseEnv());

    expect(res.meal).not.toBeNull();
    expect(res.meal!.sodium_mg).toBe(50);
    expect(res.meal!.iron_mg).toBe(2.3);
    // Out-of-range micros should be omitted entirely
    expect(res.meal!.fiber_g).toBeUndefined();
    expect(res.meal!.vitamin_c_mg).toBeUndefined();
  });

  it("writes to KV cache after a successful LLM parse", async () => {
    mockChat.mockResolvedValueOnce({
      content: JSON.stringify({
        name: "Oatmeal",
        detail: "Plain, 1 cup",
        kcal: 150,
        protein_g: 5,
        carbs_g: 27,
        fat_g: 3,
        slot: "breakfast",
        confidence: 0.88,
      }),
      provider: "wafer",
      model: "test-model",
      latencyMs: 50,
    });

    const kv = mockKV();
    const env = baseEnv({ FOOD_KV: kv });
    const res = await parseTranscript("oatmeal", null, env);

    expect(res.meal).not.toBeNull();
    // KV.put should have been called with the cache key
    expect(kv.put).toHaveBeenCalledTimes(1);
    const [putKey, putValue] = kv.put.mock.calls[0];
    expect(putKey).toContain("meal:");
    const stored = JSON.parse(putValue);
    expect(stored.meal.name).toBe("Oatmeal");
  });

  it("passes followUpAnswer into the LLM user message", async () => {
    mockChat.mockResolvedValueOnce({
      content: JSON.stringify({
        name: "Large Coffee",
        detail: "Black, 16 oz",
        kcal: 5,
        protein_g: 0,
        carbs_g: 0,
        fat_g: 0,
        slot: "breakfast",
        confidence: 0.9,
      }),
      provider: "wafer",
      model: "test-model",
      latencyMs: 25,
    });

    await parseTranscript("coffee", "large", baseEnv());

    expect(mockChat).toHaveBeenCalledTimes(1);
    const callArgs = mockChat.mock.calls[0][0];
    const userMsg = callArgs.messages.find(
      (m: { role: string }) => m.role === "user"
    );
    expect(userMsg.content).toContain("coffee");
    expect(userMsg.content).toContain("large");
    expect(userMsg.content).toContain("follow-up answer");
  });
});

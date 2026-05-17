import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { callLLM, type CallOptions } from "../../src/ai/providerPool";
import type { Env } from "../../src/types";

const simpleOpts: CallOptions = {
  messages: [{ role: "user", content: "hello" }],
};

// ---------------------------------------------------------------------------
// No keys at all → exhaustion error
// ---------------------------------------------------------------------------
describe("callLLM with no API keys", () => {
  it("throws 'All providers exhausted' when env has no keys", async () => {
    const env: Env = {};
    await expect(callLLM(simpleOpts, env)).rejects.toThrow(
      "All providers exhausted"
    );
  });
});

// ---------------------------------------------------------------------------
// Provider key collection (indirect via callLLM + mocked fetch)
// ---------------------------------------------------------------------------
describe("callLLM with mocked fetch", () => {
  const originalFetch = globalThis.fetch;

  beforeEach(() => {
    // Default mock: return a valid OpenAI-compatible chat response.
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        choices: [{ message: { content: "mocked response" } }],
      }),
      text: async () => "",
    });
  });

  afterEach(() => {
    globalThis.fetch = originalFetch;
  });

  it("uses wafer when WAFER_API_KEY is set", async () => {
    const env: Env = { WAFER_API_KEY: "waf-key-1" };
    const result = await callLLM(simpleOpts, env);

    expect(result.provider).toBe("wafer");
    expect(result.content).toBe("mocked response");
    expect(result.model).toBe("GLM-5.1");
    expect(result.latencyMs).toBeGreaterThanOrEqual(0);

    // Verify fetch was called with the wafer endpoint.
    expect(globalThis.fetch).toHaveBeenCalledWith(
      "https://pass.wafer.ai/v1/chat/completions",
      expect.objectContaining({ method: "POST" })
    );
  });

  it("tries both keys when WAFER_API_KEYS has two comma-separated keys", async () => {
    // First call fails (rate-limited), second succeeds.
    const mockFetch = vi.fn()
      .mockResolvedValueOnce({
        ok: false,
        status: 429,
        text: async () => "rate limited",
      })
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          choices: [{ message: { content: "second key worked" } }],
        }),
        text: async () => "",
      });
    globalThis.fetch = mockFetch;

    const env: Env = { WAFER_API_KEYS: "key1,key2" };
    const result = await callLLM(simpleOpts, env);

    expect(result.content).toBe("second key worked");
    expect(result.provider).toBe("wafer");
    // fetch should have been called twice: first key failed, second succeeded.
    expect(mockFetch).toHaveBeenCalledTimes(2);
  });

  it("exhausts all providers when every key fails", async () => {
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: false,
      status: 429,
      text: async () => "rate limited",
    });

    const env: Env = { WAFER_API_KEY: "bad-key" };
    await expect(callLLM(simpleOpts, env)).rejects.toThrow(
      "All providers exhausted"
    );
  });
});

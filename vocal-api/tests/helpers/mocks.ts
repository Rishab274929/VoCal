import { vi } from "vitest";

export function mockKV(store: Record<string, string> = {}): any {
  return {
    get: vi.fn(async (key: string, type?: string) => {
      const val = store[key];
      if (val === undefined) return null;
      if (type === "json") return JSON.parse(val);
      return val;
    }),
    put: vi.fn(async (key: string, value: string) => {
      store[key] = value;
    }),
  };
}

export function mockDB(overrides: Partial<ReturnType<typeof createDB>> = {}): any {
  return { ...createDB(), ...overrides };
}

function createDB() {
  return {
    prepare: vi.fn(() => mockStatement()),
    batch: vi.fn(async () => []),
  };
}

export function mockStatement(result?: any): any {
  const stmt: any = {
    bind: vi.fn((..._args: unknown[]) => stmt),
    run: vi.fn(async () => result ?? { meta: { changes: 0 } }),
    first: vi.fn(async () => null),
    all: vi.fn(async () => ({ results: [] })),
  };
  return stmt;
}

export function makeRequest(
  method: string,
  body?: unknown,
  headers: Record<string, string> = {}
): Request {
  const init: RequestInit = {
    method,
    headers: {
      "Content-Type": "application/json",
      ...headers,
    },
  };
  if (body !== undefined) {
    init.body = JSON.stringify(body);
  }
  return new Request("https://vocal.best/api/test", init);
}

export function makeAuthRequest(
  method: string,
  token: string,
  body?: unknown,
  headers: Record<string, string> = {}
): Request {
  return makeRequest(method, body, {
    Authorization: `Bearer ${token}`,
    ...headers,
  });
}

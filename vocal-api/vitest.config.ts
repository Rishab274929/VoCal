import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    globals: true,
    environment: "node",
    include: ["tests/**/*.test.ts"],
    typecheck: { enabled: false },
  },
  resolve: {
    alias: {
      "@cloudflare/workers-types": "./tests/helpers/cf-stubs.ts",
    },
  },
});

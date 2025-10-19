import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "clarinet",
    singleThread: true,
    globals: true
  },
  define: {
    __VITEST__: true
  }
});

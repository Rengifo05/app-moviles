import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
    // Las pruebas comparten el emulador: se ejecutan en serie.
    fileParallelism: false,
    testTimeout: 20000,
    hookTimeout: 20000,
  },
});

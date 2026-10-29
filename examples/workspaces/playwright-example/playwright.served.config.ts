import { defineConfig } from '@playwright/test';

// Tests a page served over HTTP (served/): `npx playwright test -c playwright.served.config.ts`.
export default defineConfig({
  testDir: './served',
  webServer: {
    command: 'node served/serve.mjs',
    url: 'http://127.0.0.1:4321',
    env: { PORT: '4321' },
    reuseExistingServer: false,
    timeout: 30_000,
  },
  use: {
    baseURL: 'http://127.0.0.1:4321',
    headless: true,
  },
  projects: [
    {
      name: 'chromium',
      use: { browserName: 'chromium' },
    },
  ],
});

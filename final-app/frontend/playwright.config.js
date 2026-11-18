const { defineConfig } = require('@playwright/test');

const requestOnlyChecks = /empty and unrecognized API responses|an unacknowledged reply|a saved reply stays saved|changing channels after a save|the inbox ignores a slow response|background refresh never retargets|a background read cannot replace/;
module.exports = defineConfig({
  testDir: './test/browser',
  workers: 1,
  projects: [
    { name: 'desktop-1366', use: { viewport: { width: 1366, height: 768 } } },
    { name: 'desktop-1920', grepInvert: requestOnlyChecks, use: { viewport: { width: 1920, height: 1080 } } },
  ],
  use: { baseURL: process.env.BASE_URL || 'http://127.0.0.1:8174',
    ...(process.env.CHROME_CHANNEL ? { channel: process.env.CHROME_CHANNEL } : {}) },
});

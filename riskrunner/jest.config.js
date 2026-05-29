module.exports = {
  testEnvironment: 'node',
  setupFiles: ['<rootDir>/__tests__/setup.js'],
  testMatch: ['**/__tests__/**/*.test.js'],
  testTimeout: 30000,
  forceExit: true,
  // Run sequentially: tests share one Firestore emulator instance
  maxWorkers: 1,
};

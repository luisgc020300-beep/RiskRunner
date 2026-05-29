// Must run before any module imports so firebase-admin connects to the emulator.
// Start emulator first: firebase emulators:start --only firestore
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = 'demo-riskrunner';

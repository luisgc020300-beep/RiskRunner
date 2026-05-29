const admin = require('firebase-admin');
const http = require('http');
// Use modular Timestamp — guaranteed to match what getFirestore() uses
const { Timestamp } = require('firebase-admin/firestore');

function db() {
  return admin.firestore();
}

// Wipes ALL documents from the Firestore emulator via its REST management API.
// More reliable than batching individual deletes across SDK boundaries.
async function clearEmulatorData() {
  return new Promise((resolve, reject) => {
    const req = http.request(
      {
        hostname: '127.0.0.1',
        port: 8080,
        path: '/emulator/v1/projects/demo-riskrunner/databases/(default)/documents',
        method: 'DELETE',
      },
      (res) => {
        res.resume();
        res.on('end', resolve);
      }
    );
    req.on('error', reject);
    req.end();
  });
}

async function seed(col, id, data) {
  await db().collection(col).doc(id).set(data);
}

// Returns a Firestore Timestamp offset from now (negative = past)
function ts(offsetMs = 0) {
  return Timestamp.fromDate(new Date(Date.now() + offsetMs));
}

module.exports = { db, clearEmulatorData, seed, ts };

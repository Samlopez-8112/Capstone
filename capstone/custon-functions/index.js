/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

const {setGlobalOptions} = require("firebase-functions");
const {onRequest} = require("firebase-functions/https");
const logger = require("firebase-functions/logger");

// For cost control, you can set the maximum number of containers that can be
// running at the same time. This helps mitigate the impact of unexpected
// traffic spikes by instead downgrading performance. This limit is a
// per-function limit. You can override the limit for each function using the
// `maxInstances` option in the function's options, e.g.
// `onRequest({ maxInstances: 5 }, (req, res) => { ... })`.
// NOTE: setGlobalOptions does not apply to functions using the v1 API. V1
// functions should each use functions.runWith({ maxInstances: 10 }) instead.
// In the v1 API, each function can only serve one request per container, so
// this will be the maximum concurrent request count.
setGlobalOptions({ maxInstances: 10 });

// Create and deploy your first functions
// https://firebase.google.com/docs/functions/get-started

// exports.helloWorld = onRequest((request, response) => {
//   logger.info("Hello logs!", {structuredData: true});
//   response.send("Hello from Firebase!");
// });

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const crypto = require("crypto");

// Initialize Firebase Admin SDK
admin.initializeApp();

// Use the secret stored in Firebase (you’ll set it below)
const ENCRYPTION_KEY = process.env.ENCRYPTION_KEY;

// Decryption helper using AES-256-CBC
function decrypt(text, base64Key) {
  const key = Buffer.from(base64Key, 'base64');
  const decipher = crypto.createDecipheriv("aes-256-cbc", key, Buffer.alloc(16, 0));
  let decrypted = decipher.update(text, "base64", "utf8");
  decrypted += decipher.final("utf8");
  return decrypted;
}

// 🔐 Lock Account Function
 exports.lockAccount = functions.https.onRequest(async (req, res) => {
  try {
    const uid = req.query.uid;
    const encryptedUid = req.query.uid;
    if (!uid || !encryptedUid) throw new Error("Missing UID");

    // 🔐 Fetch user's encryption key
    const userDoc = await admin.firestore().collection("users").doc(uid).get();
    const userData = userDoc.data();
    const userKey = userData && userData.encryptionKey;
    if (!userKey) throw new Error("User key not found");

    // Decrypt UID using this user's key
    const decryptedUid = decrypt(encryptedUid, userKey);

    // Confirm uid matches
    if (decryptedUid !== uid) throw new Error("UID mismatch");

    //Flag the account
    await admin.firestore().collection("users").doc(uid).set({
      accountLocked: true,
      lockedAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });

    res.status(200).send(`<h2>🔒 Account Locked</h2>`);
  } catch (err) {
    console.error("Error in lockAccount:", err);
    res.status(400).send("⚠️ Error processing lock request.");
  }
});
